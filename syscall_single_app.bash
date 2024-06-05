#!/bin/bash

PID=$1
DIR=$2

(cd filters && make)

mkdir -p $DIR

# set up kernel ftrace parameters
echo "function_graph" > /sys/kernel/debug/tracing/current_tracer
echo "function-fork" > /sys/kernel/debug/tracing/trace_options
echo "noirq-info" > /sys/kernel/debug/tracing/trace_options
echo "context-info" > /sys/kernel/debug/tracing/trace_options
echo "nofuncgraph-irqs" > /sys/kernel/debug/tracing/trace_options
echo "nofuncgraph-overhead" > /sys/kernel/debug/tracing/trace_options
echo "nofuncgraph-duration" > /sys/kernel/debug/tracing/trace_options
echo "nofuncgraph-tail" > /sys/kernel/debug/tracing/trace_options
echo "funcgraph-proc" > /sys/kernel/debug/tracing/trace_options
echo "0" > /sys/kernel/debug/tracing/tracing_on
echo "" > /sys/kernel/debug/tracing/trace
echo "## set up kernel ftrace parameters"

# get the pid root (docker runtime)
pstree -a -p --long $PID > $DIR/pidinfo

# get all processes under the root
cat $DIR/pidinfo \
    | cut -f 2 -d ',' \
    | cut -f 1 -d ' ' \
    | sed s/\)//g \
    | sort > $DIR/root_pids

# find kernel processes that are related to them
for p in `cat $DIR/root_pids`; do
    echo $p
    # ps -auxH |grep $p | awk '{print $2}'
done | sort | uniq > $DIR/pids
ps -auxH  > $DIR/pidinfo_more

# set pids to trace
cat $DIR/pids > /sys/kernel/debug/tracing/set_ftrace_pid

for p in `cat $DIR/pids`; do
    taskset -p 0x1 $p
done
sleep 5

echo "## tracing pids under $PID"

# start the trace
echo "1" > /sys/kernel/debug/tracing/tracing_on
echo "## started tracing"

for ((i=0;i<300;i++)); do
    sleep .1
    curl -X POST http://172.16.42.11:30550/action -H 'Content-Type: application/x-www-form-urlencoded' -d 'Name=test&Confidence=1&DateTime=1/1/1990' > /dev/null
done

echo "## finished offering load"

# stop tracing and copy trace to directory
echo "0" > /sys/kernel/debug/tracing/tracing_on
cat /sys/kernel/debug/tracing/trace > $DIR/trace
echo "## copied trace to directory"

# process the data
for p in `cat $DIR/pids`; do
    cat $DIR/trace \
        | grep $p \
        | grep -v "=>" \
        | tee $DIR/$p.raw \
        | cut -f 2 -d '|' \
        | filters/filter-errors \
        | tee $DIR/$p.filt-se \
        | filters/filter-interrupts \
        | tee $DIR/$p.filt-sei \
        | sort | uniq \
        | grep -v "}" \
        | cut -f 1 -d '(' \
        | awk '{print $1}' \
        | uniq \
        | tee $DIR/$p.list
done | sort |uniq > $DIR/trace.list

echo "## processed data"