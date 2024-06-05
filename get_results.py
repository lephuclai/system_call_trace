import os

print("Mongo function call: ")
for i in range(1, 11):
    os.system("wc -l < results/mproc_4_6_rep_" + str(i) + "/trace_mongo.list")

print("Web function call: ")
for i in range(1, 11):
    os.system("wc -l < results/mproc_4_6_rep_" + str(i) + "/trace_web.list")
