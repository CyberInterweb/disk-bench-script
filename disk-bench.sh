#!/bin/bash
# -*- coding: utf-8 -*-
#
#  disk_bench.sh
#
#  Copyright 2020 Thomas Castleman <contact@draugeros.org>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.
#
#
VERSION="0.0.3"
HELP="disk_bench.sh, Version $VERSION\n\n\t-h, --help\t\tPrint this help dialog.\n\t-o, --override\t\t(MacOS & BSD) Override lock-out and allow disk_bench.sh to attempt a full benchmark, regardless of OS support.\n\t-v, --version\t\tPrint the current version of this script.\n\nPass nothing to start the benchmark."
OS=$(uname)
ACCURACY_SCALER=2
PREFIX="/tmp"

function benchmark_write ()
{
	accuracy=$1
	PREFIX="$2"
	OS="$3"
	if [ "$OS" == "Darwin" ]; then
		SCALE="g"
		REGEX1="secs"
		REGEX2="[()]"
		REGEX3=2
	else
		SCALE="G"
		REGEX1="s,"
		REGEX2=","
		REGEX3=4
	fi
	count=0
	data=()
	while [[ $count -lt $accuracy ]]; do
		data[$count]=$(dd if=/dev/zero of="$PREFIX"/write_test.img bs=1"$SCALE" count=1 2>&1 | grep "$REGEX1" | awk -F "$REGEX2" "{print \$$REGEX3}")
		if [ "$OS" == "Linux" ]; then
			data[$count]=$(echo "${data[count]}" | sed 's/ //')
		fi
		rm "$PREFIX"/write_test.img
		count=$((count + 1))
		printf " ." 1>&2
	done
	type=$(echo "${data[0]}" | awk '{print $2}')
	count=0
	while [[ $count -lt $accuracy ]]; do
		if [ "$type" == "KB/s" ]; then
			if $(echo "${data[count]}" | grep -q "KB/s"); then
				data[$count]="${data[count]// KB\/s/}"
			elif $(echo "${data[count]}" | grep -q "MB/s"); then
				data[$count]="${data[count]// MB\/s/}"
				data[$count]=$(echo "${data[count]} / 1000" | bc -l)
			elif $(echo "${data[count]}" | grep -q "GB/s"); then
				data[$count]="${data[count]// GB\/s/}"
				data[$count]=$(echo "${data[count]} / 1000" | bc -l)
				data[$count]=$(echo "${data[count]} / 1000" | bc -l)
			fi
		elif [ "$type" == "MB/s" ]; then
			if $(echo "${data[count]}" | grep -q "KB/s"); then
				data[$count]="${data[count]// KB\/s/}"
				data[$count]=$(echo "${data[count]} * 1000" | bc -l)
			elif $(echo "${data[count]}" | grep -q "MB/s"); then
				data[$count]="${data[count]// MB\/s/}"
			elif $(echo "${data[count]}" | grep -q "GB/s"); then
				data[$count]="${data[count]// GB\/s/}"
				data[$count]=$(echo "${data[count]} / 1000" | bc -l)
			fi
		elif [ "$type" == "GB/s" ]; then
			if $(echo "${data[count]}" | grep -q "KB/s"); then
				data[$count]="${data[count]// KB\/s/}"
				data[$count]=$(echo "${data[count]} * 1000" | bc -l)
				data[$count]=$(echo "${data[count]} * 1000" | bc -l)
			elif $(echo "${data[count]}" | grep -q "MB/s"); then
				data[$count]="${data[count]// MB\/s/}"
				data[$count]=$(echo "${data[count]} * 1000" | bc -l)
			elif $(echo "${data[count]}" | grep -q "GB/s"); then
				data[$count]="${data[count]// GB\/s/}"
			fi
		elif [ "$type" == "bytes/sec" ]; then
			data[$count]="${data[count]// bytes\/sec/}"
		fi
		count=$((count + 1))
	done
	total=0
	for each in "${data[@]}"; do
		total=$(echo "$total + $each" | bc -l)
	done
	total=$(echo "$total / $count" | bc -l)
	echo "$total $type"
}

function benchmark_read ()
{
	lsblk --output NAME,TYPE,LABEL,FSSIZE,MOUNTPOINT | grep -v '^loop'
	echo ""
	read -rp "What device are we benchmarking? [input NAME, 'exit' to exit benchmarks, 'skip' to continue to write benchmark]: " NAME
	if [ "$NAME" == "exit" ] || [ "$NAME" == "quit" ]; then
		exit 1
	elif [ "$NAME" == "skip" ] || [ "$NAME" == "continue" ]; then
		return 1
	else
		NAME="${NAME//\/dev\//}"
	fi
	echo -e "\nNOTICE: REQUESTING ROOT ACCESS TO BENCHMARK DRIVE OR PARTITION\n"
	sudo hdparm -Tt /dev/"$NAME"
}

function benchmark_latency ()
{
	accuracy=$1
	PREFIX="$2"
	OS="$3"
	if [ "$OS" == "Darwin" ]; then
		REGEX1="secs"
		REGEX2=" "
		REGEX3=5
	else
		REGEX1="s,"
		REGEX2=","
		REGEX3=3
	fi
	count=0
	data=()
	while [[ $count -lt $accuracy ]]; do
		data[$count]=$(dd if=/dev/zero of="$PREFIX"/latency_test.img bs=512 count=1000 2>&1 | grep "$REGEX1" | awk -F "$REGEX2" "{print \$$REGEX3}" | sed 's/ s//g' | sed 's/ //g')
		rm "$PREFIX"/latency_test.img
		count=$((count + 1))
		printf " ." 1>&2
	done
	total=0
	for each in "${data[@]}"; do
		total=$(echo "$total + $each" | bc -l)
	done
	total=$(echo "$total / $count" | bc -l)
	echo "$total"
}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
	echo -e "$HELP"
elif [ "$1" == "-v" ] || [ "$1" == "--version" ]; then
	echo -e "$VERSION"
elif [ "$1" == "" ] || [ "$1" == " " ] || [ "$1" == "--override" ] || [ "$1" == "-o" ]; then
	if [ "$OS" == "Darwin" ]; then
		if [ "$1" != "--override" ] || [ "$1" != "-o" ]; then
			echo "Starting Benchmarks . . ."
			#PREFIX="$PWD"
			read -rp "Latency Benchmark Accuracy [1-10]: " accuracy
			accuracy=$((accuracy * ACCURACY_SCALER))
			printf "Running Disk Latency Benchmark"
			result=$(benchmark_latency $accuracy "$PREFIX" "$OS")
			echo ""
			echo "LATENCY: $result s"
			read -rp "Write Speed Benchmark Accuracy [1-10]: " accuracy
			accuracy=$((accuracy * ACCURACY_SCALER))
			printf "Running Disk Write Speed Benchmark"
			result=$(benchmark_write $accuracy "$PREFIX" "$OS")
			echo ""
			echo "WRITE SPEED: $result"
		elif [ "$1" == "--override" ] || [ "$1" == "-o" ]; then
			echo "Starting Benchmarks . . ."
			#PREFIX="$PWD"
			echo "WARNING: OVERRIDE FLAG SET. IT IS UNKNOWN WHETHER YOUR OS SUPPORTS ALL BENCHMARKS. EXPECT BUGS." 1>&2
			read -rp "Latency Benchmark Accuracy [1-10]: " accuracy
			accuracy=$((accuracy * ACCURACY_SCALER))
			printf "Running Disk Latency Benchmark"
			result=$(benchmark_latency $accuracy "$PREFIX" "$OS")
			echo ""
			echo "LATENCY: $result s"
			benchmark_read
			read -rp "Write Speed Benchmark Accuracy [1-10]: " accuracy
			accuracy=$((accuracy * ACCURACY_SCALER))
			printf "Running Disk Write Speed Benchmark"
			result=$(benchmark_write $accuracy "$PREFIX" "$OS")
			echo ""
			echo "WRITE SPEED: $result"
		fi
	elif [ "$OS" == "Linux" ]; then
		echo "Starting Benchmarks . . ."
		read -rp "Latency Benchmark Accuracy [1-10]: " accuracy
		accuracy=$((accuracy * ACCURACY_SCALER))
		printf "Running Disk Latency Benchmark"
		result=$(benchmark_latency $accuracy "$PREFIX" "$OS")
		echo ""
		echo "LATENCY: $result s"
		benchmark_read
		read -rp "Write Speed Benchmark Accuracy [1-10]: " accuracy
		accuracy=$((accuracy * ACCURACY_SCALER))
		printf "Running Disk Write Speed Benchmark"
		result=$(benchmark_write $accuracy "$PREFIX" "$OS")
		echo ""
		echo "WRITE SPEED: $result"
	fi
else
	echo "$1: INPUT NOT RECOGNIZED" 1>&2
	echo -e "$HELP"
fi
