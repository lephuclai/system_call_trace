from variables import *
from kubernetes import client, config
import time
import sys
import paramiko
import os

DIR = sys.argv[1]

# SSH to worker
def remote_worker_connect(host_username: str, host_ip: str, host_pass: str, event=None):
    print("Trying to connect to remote host {}, IP: {}".format(
        host_username, host_ip))
    try:
        global worker_client 
        worker_client = paramiko.SSHClient()
        worker_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        worker_client.connect(host_ip, username=host_username,
                       password=host_pass)
    except paramiko.AuthenticationException:
        print("Authentication failed when connecting to %s" % host_ip)
        sys.exit(1)
    except:
        print("Could not SSH to %s, waiting for it to start" % host_ip)
    if event is not None:
        event.set()

# Execute command in worker
def remote_worker_command(command: str):
    print(command)
    stdin, stdout, stderr = worker_client.exec_command(command, get_pty=True)
    # stdin.write(MEC_PASSWORD + '\n')
    stdin.flush()

    # Return output of executed command
    output = ""
    for line in stdout:
        output += line.strip('\n') + "\n"
    return output.strip()

# Load Kubernetes configuration
config.load_kube_config()

# Create CoreV1Api instance
v1 = client.CoreV1Api()

def measure_mpod(num: int):
    remote_worker_connect(MEC_USERNAME, MEC_IP, MEC_PASSWORD)

    os.system("kubectl apply -f microservices_deploy/mongo.yaml")
    os.system("kubectl apply -f microservices_deploy/web.yaml")

    time.sleep(30)

    mongo_pod_id = remote_worker_command("sudo crictl ps | grep mongo | awk '{print $9}' | head -1")
    print("Pod ID: " + mongo_pod_id)
    mongo_PID = remote_worker_command("pstree -a -p --long | grep " + mongo_pod_id + " | cut -f 2 -d ',' | cut -f 1 -d ' ' | head -1")
    print("Pod PID: " + mongo_PID)

    web_pod_id = remote_worker_command("sudo crictl ps | grep web | awk '{print $9}' | head -1")
    print("Pod ID: " + web_pod_id)
    web_PID = remote_worker_command("pstree -a -p --long | grep " + web_pod_id + " | cut -f 2 -d ',' | cut -f 1 -d ' ' | head -1")
    print("Pod PID: " + web_PID)    

    remote_worker_command("cd /home/kien/systemcall_trace/ ; sudo ./syscall.bash " + mongo_PID + " " + web_PID + " " + DIR + str(num))

    time.sleep(5)

    os.system("kubectl delete -f microservices_deploy/mongo.yaml")
    os.system("kubectl delete -f microservices_deploy/web.yaml")

    time.sleep(60)


def measure_mcont(num: int):
    remote_worker_connect(MEC_USERNAME, MEC_IP, MEC_PASSWORD)

    os.system("kubectl apply -f microservices_deploy/multi_container.yaml")

    time.sleep(30)

    pod_id = remote_worker_command("sudo crictl ps | grep mongo | awk '{print $9}' | head -1")
    print("Pod ID: " + pod_id)
    pod_PID = remote_worker_command("pstree -a -p --long | grep " + pod_id + " | cut -f 2 -d ',' | cut -f 1 -d ' ' | head -1")
    print("Pod PID: " + pod_PID)

    mongo_PID = remote_worker_command("pstree -a -p --long " + pod_PID + " | grep -E 'mongod,.* --auth --bind_ip_all' | awk -F, '{print $2}' | awk '{print $1}'")
    web_PID = remote_worker_command("pstree -a -p --long " + pod_PID + "| grep -E 'sh,.* -c gunicorn -w 4 -b 0.0.0.0:5500 app:application' | awk -F, '{print $2}' | awk '{print $1}'")

    remote_worker_command("cd /home/kien/systemcall_trace/ ; sudo ./syscall.bash " + mongo_PID + " " + web_PID + " " + DIR + str(num))

    time.sleep(5)

    os.system("kubectl delete -f microservices_deploy/multi_container.yaml")

    time.sleep(60)    

def measure_mproc(num: int):
    remote_worker_connect(MEC_USERNAME, MEC_IP, MEC_PASSWORD)

    os.system("kubectl apply -f microservices_deploy/multi_process.yaml")

    time.sleep(30)

    pod_id = remote_worker_command("sudo crictl ps | grep mproc | awk '{print $9}' | head -1")
    print("Pod ID: " + pod_id)
    pod_PID = remote_worker_command("pstree -a -p --long | grep " + pod_id + " | cut -f 2 -d ',' | cut -f 1 -d ' ' | head -1")
    print("Pod PID: " + pod_PID)

    web_PID = remote_worker_command("pstree -a -p --long " + pod_PID + " | grep -E 'gunicorn,.* /usr/local/bin/gunicorn -w 4 -b 0.0.0.0:5500 app:application' | awk -F',' '{print $2}' | awk '{print $1}' | head -1")
    mongo_PID = remote_worker_command("pstree -a -p --long " + pod_PID + "| grep -E 'mongod,.* --bind_ip_all' | awk -F',' '{print $2}' | awk '{print $1}' | head -1")

    remote_worker_command("cd /home/kien/systemcall_trace/ ; sudo ./syscall.bash " + mongo_PID + " " + web_PID + " " + DIR + str(num))

    time.sleep(5)

    os.system("kubectl delete -f microservices_deploy/multi_process.yaml")

    time.sleep(150)     


num = 1
for i in range (1, 11):
    measure_mproc(num)
    num += 1