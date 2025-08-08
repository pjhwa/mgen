import re
import sys
import statistics
import csv
from datetime import datetime
from collections import defaultdict

def parse_mgen_log(log_file):
    """
    MGEN 로그 파일 파싱: RECV 이벤트 추출.
    반환: 리스트 of dicts {seq, sent_time, recv_time, size, latency}
    """
    recv_events = []
    with open(log_file, 'r') as f:
        for line in f:
            if 'RECV' in line and 'REPORT' not in line:  # REPORT 라인 제외
                match = re.search(r'(\d{2}:\d{2}:\d{2}\.\d+) RECV .*seq>(\d+) .*sent>(\d{2}:\d{2}:\d{2}\.\d+) size>(\d+)', line)
                if match:
                    recv_time_str, seq, sent_time_str, size = match.groups()
                    try:
                        recv_time = datetime.strptime(recv_time_str, '%H:%M:%S.%f')
                        sent_time = datetime.strptime(sent_time_str, '%H:%M:%S.%f')
                        latency = (recv_time - sent_time).total_seconds()
                        recv_events.append({
                            'seq': int(seq),
                            'sent_time': sent_time,
                            'recv_time': recv_time,
                            'size': int(size),
                            'latency': latency
                        })
                    except ValueError:
                        continue  # 타임스탬프 파싱 오류 스킵
    return recv_events

def analyze_metrics(events):
    """
    메트릭스 계산: throughput (Mbits/sec), jitter (ms), loss rate (%)
    """
    if not events:
        return {'throughput_mbits_sec': 0, 'jitter_ms': 0, 'loss_rate_percent': 100, 'avg_latency_ms': 0, 'transfer_bytes': 0, 'duration_sec': 0, 'lost_total': '0/0'}

    seqs = [e['seq'] for e in events]
    min_seq, max_seq = min(seqs), max(seqs)
    expected_msgs = max_seq - min_seq + 1
    received_msgs = len(events)
    loss_rate = ((expected_msgs - received_msgs) / expected_msgs) * 100 if expected_msgs else 100
    lost_total = f"{expected_msgs - received_msgs}/{expected_msgs} ({loss_rate:.1f}%)"

    total_bytes = sum(e['size'] for e in events)
    start_time = min(e['recv_time'] for e in events)
    end_time = max(e['recv_time'] for e in events)
    duration = (end_time - start_time).total_seconds()
    throughput_mbits_sec = (total_bytes * 8 / 1_000_000) / duration if duration > 0 else 0  # Mbits/sec

    latencies = [e['latency'] * 1000 for e in events]  # ms 단위
    jitter = statistics.stdev(latencies) if len(latencies) > 1 else 0  # 표준편차로 지터
    avg_latency = statistics.mean(latencies) if latencies else 0

    return {
        'throughput_mbits_sec': round(throughput_mbits_sec, 2),
        'jitter_ms': round(jitter, 3),  # iperf처럼 소수점 3자리
        'loss_rate_percent': round(loss_rate, 1),
        'avg_latency_ms': round(avg_latency, 3),
        'transfer_bytes': total_bytes,
        'duration_sec': round(duration, 1),
        'lost_total': lost_total
    }

def print_iperf_like_table(host, metrics):
    """
    iperf-like 테이블 형식으로 콘솔 출력
    """
    print(f"[ ID] Interval       Transfer     Bandwidth       Jitter    Lost/Total Datagrams")
    print(f"[  1] 0.0-{metrics['duration_sec']} sec   {metrics['transfer_bytes']/1_000_000:.2f} MBytes  {metrics['throughput_mbits_sec']} Mbits/sec  {metrics['jitter_ms']} ms  {metrics['lost_total']}")

def print_summary(all_metrics):
    """
    모든 호스트 메트릭스 요약: 평균, MIN, MAX 출력
    """
    if not all_metrics:
        print("Summary: No data available.")
        return

    # 각 메트릭스 리스트 추출
    throughputs = [m['throughput_mbits_sec'] for m in all_metrics]
    jitters = [m['jitter_ms'] for m in all_metrics]
    losses = [m['loss_rate_percent'] for m in all_metrics]
    latencies = [m['avg_latency_ms'] for m in all_metrics]

    # 평균 계산
    avg_throughput = round(statistics.mean(throughputs), 2) if throughputs else 0
    avg_jitter = round(statistics.mean(jitters), 3) if jitters else 0
    avg_loss = round(statistics.mean(losses), 1) if losses else 0
    avg_latency = round(statistics.mean(latencies), 3) if latencies else 0

    # MIN/MAX 계산
    min_throughput = round(min(throughputs), 2) if throughputs else 0
    max_throughput = round(max(throughputs), 2) if throughputs else 0
    min_jitter = round(min(jitters), 3) if jitters else 0
    max_jitter = round(max(jitters), 3) if jitters else 0
    min_loss = round(min(losses), 1) if losses else 0
    max_loss = round(max(losses), 1) if losses else 0
    min_latency = round(min(latencies), 3) if latencies else 0
    max_latency = round(max(latencies), 3) if latencies else 0

    print("\nSummary (Across all receivers):")
    print(f"Metric             Average      MIN          MAX")
    print(f"Throughput (Mbits/sec) {avg_throughput:<12} {min_throughput:<12} {max_throughput}")
    print(f"Jitter (ms)        {avg_jitter:<12} {min_jitter:<12} {max_jitter}")
    print(f"Loss Rate (%)      {avg_loss:<12} {min_loss:<12} {max_loss}")
    print(f"Avg Latency (ms)   {avg_latency:<12} {min_latency:<12} {max_latency}")

def main(log_files, output_csv):
    """
    여러 로그 파일 분석 및 CSV 출력.
    log_files: 리스트 of 파일 경로 (e.g., ['host1_log.txt', 'host2_log.txt'])
    """
    all_metrics = []  # 모든 호스트 메트릭스 수집 리스트
    results = defaultdict(dict)
    with open(output_csv, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=['host', 'throughput_mbits_sec', 'jitter_ms', 'loss_rate_percent', 'avg_latency_ms'])
        writer.writeheader()

        for log in log_files:
            host = log.split('_')[0]  # 파일명에서 호스트 추출
            events = parse_mgen_log(log)
            metrics = analyze_metrics(events)
            metrics['host'] = host
            all_metrics.append(metrics)  # 요약용 리스트 추가
            writer.writerow({
                'host': host,
                'throughput_mbits_sec': metrics['throughput_mbits_sec'],
                'jitter_ms': metrics['jitter_ms'],
                'loss_rate_percent': metrics['loss_rate_percent'],
                'avg_latency_ms': metrics['avg_latency_ms']
            })
            print_iperf_like_table(host, metrics)  # iperf-like 출력 추가

    # 모든 분석 후 요약 출력
    print_summary(all_metrics)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("사용법: python analyze_mgen.py log1.txt log2.txt ... output.csv")
        sys.exit(1)
    log_files = sys.argv[1:-1]
    output_csv = sys.argv[-1]
    main(log_files, output_csv)
