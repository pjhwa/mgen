#!/bin/bash

# 스크립트 이름: automation.sh
# 실행 방법: k1 root에서 bash automation.sh
# 가정: sender.mgn과 analyze_mgen.py는 /root/에 있음.
#       receiver.mgn은 k2/k3/k4의 /root/에 있음, output 경로 /home/citec/로 수정.
#       ssh 키 기반 접속 가능 (패스워드 입력 없음).
#       logs/ 디렉토리: /root/logs/ (자동 생성).

# 수신 서버 리스트
RECEIVERS=("k2" "k3" "k4")

# 로그 디렉토리 생성
mkdir -p /root/logs

# 단계 1: 각 수신 서버에서 mgen 실행
for receiver in "${RECEIVERS[@]}"; do
    echo "Starting mgen on $receiver..."
    ssh citec@$receiver "sudo mgen input /root/receiver.mgn output /home/citec/receiver_${receiver}.log && sudo chown citec:citec /home/citec/receiver_${receiver}.log" &
    # 백그라운드 실행 (&), chown으로 citec 소유 변경
    sleep 5  # 안정성 위해 지연
done

# 단계 2: 송신 서버(k1)에서 mgen 실행 및 대기
echo "Starting mgen on sender (k1)..."
mgen input /root/sender.mgn txlog output /root/sender_log.txt
if [ $? -ne 0 ]; then
    echo "Error: Sender mgen failed."
    exit 1
fi
echo "Sender mgen completed."

# 단계 3: 수신 서버 mgen 종료
for receiver in "${RECEIVERS[@]}"; do
    echo "Stopping mgen on $receiver..."
    ssh citec@$receiver "sudo pkill -15 mgen"  # SIGTERM으로 안전 종료
done

# 단계 4: 로그 파일 수집 (/root/logs/로 복사)
for receiver in "${RECEIVERS[@]}"; do
    echo "Collecting log from $receiver..."
    scp citec@$receiver:/home/citec/receiver_${receiver}.log /root/logs/ || {
        echo "Error: Failed to collect log from $receiver."
        continue
    }
done

# 단계 5: 분석 스크립트 실행
echo "Analyzing logs..."
log_files=$(ls /root/logs/receiver_*.log 2>/dev/null)
if [ -z "$log_files" ]; then
    echo "Error: No log files found in /root/logs/"
    exit 1
fi
python3 /root/analyze_mgen2.py $log_files /root/logs/analysis_result.csv
if [ $? -ne 0 ]; then
    echo "Error: Analysis script failed."
    exit 1
fi

echo "Automation completed. Results in /root/logs/analysis_result.csv and console."
