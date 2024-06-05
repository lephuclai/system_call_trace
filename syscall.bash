#!/bin/bash

PID_mongo=$1
PID_web=$2
DIR=$3

# build the filter
(cd filters && make)

# make the results directory
mkdir -p $DIR

# set up kernel ftrace parameters
echo "function_graph" > /sys/kernel/debug/tracing/current_tracer         #select function_graph tracer
echo "function-fork" > /sys/kernel/debug/tracing/trace_options           #set this option to have the child PIDs of a task traced as well
echo "noirq-info" > /sys/kernel/debug/tracing/trace_options              #
echo "context-info" > /sys/kernel/debug/tracing/trace_options            #show only the event data. Hides the comm, PID, timestamp, CPU, and other data
echo "nofuncgraph-irqs" > /sys/kernel/debug/tracing/trace_options        #hide the overhead field
echo "nofuncgraph-overhead" > /sys/kernel/debug/tracing/trace_options    #
echo "nofuncgraph-duration" > /sys/kernel/debug/tracing/trace_options    #hide function's time of execution
echo "nofuncgraph-tail" > /sys/kernel/debug/tracing/trace_options        #
echo "funcgraph-proc" > /sys/kernel/debug/tracing/trace_options          #enabling this options has the command of each process displayed at every line
echo "0" > /sys/kernel/debug/tracing/tracing_on                          #turn off tracing
echo "" > /sys/kernel/debug/tracing/trace                                #clear previous tracing results
echo "## set up kernel ftrace parameters"

# get the pid root of service
pstree -a -p --long $PID_mongo > $DIR/pidinfo_mongo
pstree -a -p --long $PID_web > $DIR/pidinfo_web

# get all processes under the root
cat $DIR/pidinfo_mongo \
    | cut -f 2 -d ',' \
    | cut -f 1 -d ' ' \
    | sed s/\)//g \
    | sort > $DIR/pids_mongo

cat $DIR/pidinfo_web \
    | cut -f 2 -d ',' \
    | cut -f 1 -d ' ' \
    | sed s/\)//g \
    | sort > $DIR/pids_web

# get all of the current process
ps -auxH  > $DIR/pidinfo_more

# set pids to trace
cat $DIR/pids_mongo $DIR/pids_web > /sys/kernel/debug/tracing/set_ftrace_pid

# pin process to core 0 of cpu
for p in `cat $DIR/pids_mongo`; do
    taskset -p 0x1 $p
done

for p in `cat $DIR/pids_web`; do
    taskset -p 0x1 $p
done

sleep 5

# start the trace
echo "## tracing pids under $PID_mongo and $PID_web"

echo "1" > /sys/kernel/debug/tracing/tracing_on
echo "## started tracing"

# generate load
for ((i=0;i<300;i++)); do
    sleep .1
    curl -X POST http://172.16.42.11:30550/action -H 'Content-Type: application/x-www-form-urlencoded' -d 'Name=test&Confidence=1&DateTime=1/1/1990' > /dev/null
done

echo "## finished offering load"

# stop tracing and copy trace to the result directory
echo "0" > /sys/kernel/debug/tracing/tracing_on
cat /sys/kernel/debug/tracing/trace > $DIR/trace
echo "## copied trace to directory"

# process the data
for p in `cat $DIR/pids_mongo`; do
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
done | sort |uniq > $DIR/trace_mongo.list

for p in `cat $DIR/pids_web`; do
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
done | sort |uniq > $DIR/trace_web.list

echo "## processed data"