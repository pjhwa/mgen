#!/bin/bash

# 스크립트 이름: full_automation.sh
# 실행 방법: k1 root에서 bash full_automation.sh
# 가정: sender.mgn 템플릿(기본 내용, PERIODIC 부분 동적 수정), receiver.mgn은 /root/에 있음 (output /home/citec/로 설정).
#       analyze_mgen.py는 /root/에 있음.
#       ssh 키 기반 접속 가능, citec sudo nopasswd 설정 가정.
#       VM 리스트: k2~k10 (9 VM까지 지원, 필요 시 확장).
#       결과 파일: /root/test_results.md (Markdown 테이블), /root/test_results.csv (CSV 테이블).

# 수신 VM 전체 리스트 (k2~k10 가정)
ALL_RECEIVERS=("k2" "k3" "k4" "k5" "k6" "k7" "k8" "k9" "k10")

# 시나리오 정의 (rate in k pps)
SCENARIOS=(100 50 30)
VM_COUNTS=(3 6 9)

# 결과 테이블 헤더 (Markdown)
echo "| 부하시나리오 | receiver VM배치 | bandwidth(Mb/s) | Jitter(ms) | Loss율(%) | PPS | Avg Latency(ms) |" > /root/test_results.md
echo "|------------|----------------|-----------------|----------|----------|-----|-----------------|" >> /root/test_results.md

# 결과 테이블 헤더 (CSV)
echo "부하시나리오,receiver VM배치,\"bandwidth(Mb/s)\",\"Jitter(ms)\",\"Loss율(%)\",\"PPS\",\"Avg Latency(ms)\"" > /root/test_results.csv

# 각 시나리오 루프
for rate in "${SCENARIOS[@]}"; do
    for vm_count in "${VM_COUNTS[@]}"; do
        echo "Running test: ${rate}k pps, 256B, ${vm_count} VMs..."

        # 동적 RECEIVERS 선택 (ALL_RECEIVERS에서 슬라이스)
        RECEIVERS=("${ALL_RECEIVERS[@]:0:$vm_count}")

        # sender.mgn 동적 생성 (기본 템플릿 + PERIODIC 수정)
        cat << EOF > /root/sender.mgn
# Global Commands
START NOW
TXBUFFER 65536
RXBUFFER 65536
BROADCAST ON
TTL 1

# Transmission Events
0.0 ON 1 UDP DST 255.255.255.255/5000 PERIODIC [${rate}000 256]
10.0 OFF 1
EOF

        # 케이스별 로그 디렉토리 생성
        CASE_DIR="/root/logs/case_${rate}k_${vm_count}vm"
        mkdir -p $CASE_DIR

        # 단계 1: 각 수신 서버에서 mgen 실행
        for receiver in "${RECEIVERS[@]}"; do
            echo "Starting mgen on $receiver..."
            ssh citec@$receiver "sudo mgen input /root/receiver.mgn output /home/citec/receiver_${receiver}.log && sudo chown citec:citec /home/citec/receiver_${receiver}.log" &
            sleep 2  # 지연으로 안정성 확보
        done

        # 단계 2: 송신 mgen 실행
        echo "Starting sender mgen..."
        mgen input /root/sender.mgn txlog output /root/sender_log.txt
        if [ $? -ne 0 ]; then
            echo "Error: Sender mgen failed."
            continue
        fi

        # 단계 3: 수신 mgen 종료
        for receiver in "${RECEIVERS[@]}"; do
            echo "Stopping mgen on $receiver..."
            ssh citec@$receiver "sudo pkill -15 mgen"
        done

        # 단계 4: 로그 수집
        for receiver in "${RECEIVERS[@]}"; do
            echo "Collecting log from $receiver..."
            scp citec@$receiver:/home/citec/receiver_${receiver}.log $CASE_DIR/ || {
                echo "Error: Failed to collect log from $receiver."
                continue
            }
        done

        # 단계 5: 분석 실행
        echo "Analyzing logs for this case..."
        log_files=$(ls $CASE_DIR/receiver_*.log 2>/dev/null)
        if [ -z "$log_files" ]; then
            echo "Error: No log files found for this case."
            continue
        fi
        python3 /root/analyze_mgen2.py $log_files $CASE_DIR/analysis_result.csv > $CASE_DIR/analysis_output.txt

        # 단계 6: 분석 결과 파싱 (Summary 섹션에서 Avg/Min/Max 추출, N/A로 기본값 처리)
        SUMMARY_FILE="$CASE_DIR/analysis_output.txt"
        BW_AVG=$(grep "^Throughput (Mbits/sec)" $SUMMARY_FILE | awk '{print $(NF-2)}' || echo "N/A")
        BW_MIN=$(grep "^Throughput (Mbits/sec)" $SUMMARY_FILE | awk '{print $(NF-1)}' || echo "N/A")
        BW_MAX=$(grep "^Throughput (Mbits/sec)" $SUMMARY_FILE | awk '{print $NF}' || echo "N/A")
        JITTER_AVG=$(grep "^Jitter (ms)" $SUMMARY_FILE | awk '{print $(NF-2)}' || echo "N/A")
        JITTER_MIN=$(grep "^Jitter (ms)" $SUMMARY_FILE | awk '{print $(NF-1)}' || echo "N/A")
        JITTER_MAX=$(grep "^Jitter (ms)" $SUMMARY_FILE | awk '{print $NF}' || echo "N/A")
        LOSS_AVG=$(grep "^Loss Rate (%)" $SUMMARY_FILE | awk '{print $(NF-2)}' || echo "N/A")
        LOSS_MIN=$(grep "^Loss Rate (%)" $SUMMARY_FILE | awk '{print $(NF-1)}' || echo "N/A")
        LOSS_MAX=$(grep "^Loss Rate (%)" $SUMMARY_FILE | awk '{print $NF}' || echo "N/A")
        PPS_AVG=$(grep "^PPS" $SUMMARY_FILE | awk '{print $(NF-2)}' || echo "N/A")
        PPS_MIN=$(grep "^PPS" $SUMMARY_FILE | awk '{print $(NF-1)}' || echo "N/A")
        PPS_MAX=$(grep "^PPS" $SUMMARY_FILE | awk '{print $NF}' || echo "N/A")
        LATENCY_AVG=$(grep "^Avg Latency (ms)" $SUMMARY_FILE | awk '{print $(NF-2)}' || echo "N/A")
        LATENCY_MIN=$(grep "^Avg Latency (ms)" $SUMMARY_FILE | awk '{print $(NF-1)}' || echo "N/A")
        LATENCY_MAX=$(grep "^Avg Latency (ms)" $SUMMARY_FILE | awk '{print $NF}' || echo "N/A")

        # Markdown 행 추가
        echo "| 256B, ${rate}k pps | ${vm_count} VM | Avg(${BW_AVG}), Min(${BW_MIN}), Max(${BW_MAX}) | Avg(${JITTER_AVG}), Min(${JITTER_MIN}), Max(${JITTER_MAX}) | Avg(${LOSS_AVG}), Min(${LOSS_MIN}), Max(${LOSS_MAX}) | Avg(${PPS_AVG}), Min(${PPS_MIN}), Max(${PPS_MAX}) | Avg(${LATENCY_AVG}), Min(${LATENCY_MIN}), Max(${LATENCY_MAX}) |" >> /root/test_results.md

        # CSV 행 추가 (따옴표로 복잡한 값 감싸기)
        echo "256B, ${rate}k pps,${vm_count} VM,\"Avg(${BW_AVG}), Min(${BW_MIN}), Max(${BW_MAX})\",\"Avg(${JITTER_AVG}), Min(${JITTER_MIN}), Max(${JITTER_MAX})\",\"Avg(${LOSS_AVG}), Min(${LOSS_MIN}), Max(${LOSS_MAX})\",\"Avg(${PPS_AVG}), Min(${PPS_MIN}), Max(${PPS_MAX})\",\"Avg(${LATENCY_AVG}), Min(${LATENCY_MIN}), Max(${LATENCY_MAX})\"" >> /root/test_results.csv
    done
done

echo "All tests completed. Results in /root/test_results.md and /root/test_results.csv"
cat /root/test_results.md  # 콘솔에 Markdown 표 출력
