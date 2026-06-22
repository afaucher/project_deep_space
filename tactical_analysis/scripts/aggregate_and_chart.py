import csv
import statistics
from collections import defaultdict
import os

def read_csv(filepath):
    data = []
    if not os.path.exists(filepath):
        print(f"Warning: {filepath} not found.")
        return data
        
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if not row or not any(row.values()):
                continue
            data.append(row)
    return data

def aggregate_missile_pd(data):
    # group by (num_missiles, engagement_range, axis)
    groups = defaultdict(list)
    for row in data:
        key = (int(row['num_missiles']), float(row['engagement_range']), row['axis'])
        groups[key].append({
            'hits': int(row['hits']),
            'destroyed': int(row['destroyed']),
            'timeouts': int(row['timeouts']),
            'ship_killed': int(row['ship_killed']),
            'hits_taken': int(row['hits_taken'])
        })
        
    markdown_table = "| Missiles Fired | Range (m) | Axis | Hit Prob (%) | Avg Hits | Avg Destroyed | Kill Rate (%) | Avg Hits to Kill |\n"
    markdown_table += "|----------------|-----------|------|--------------|----------|---------------|---------------|------------------|\n"
    
    for key in sorted(groups.keys()):
        runs = groups[key]
        num_missiles, rnge, axis = key
        
        hit_probs = [run['hits'] / num_missiles * 100 for run in runs]
        avg_hits = statistics.mean([run['hits'] for run in runs])
        avg_pd = statistics.mean([run['destroyed'] for run in runs])
        
        kill_rates = [run['ship_killed'] * 100 for run in runs]
        avg_kill_rate = statistics.mean(kill_rates)
        
        # Only average hits taken if the ship was killed
        hits_to_kill = [run['hits_taken'] for run in runs if run['ship_killed'] == 1]
        avg_hits_to_kill = statistics.mean(hits_to_kill) if len(hits_to_kill) > 0 else 0.0
        
        avg_prob = statistics.mean(hit_probs)
        std_prob = statistics.stdev(hit_probs) if len(hit_probs) > 1 else 0.0
        
        markdown_table += f"| {num_missiles} | {rnge} | {axis} | {avg_prob:.1f}% ±{std_prob:.1f}% | {avg_hits:.1f} | {avg_pd:.1f} | {avg_kill_rate:.1f}% | {avg_hits_to_kill:.1f} |\n"
        
    return markdown_table

def aggregate_ttk(data):
    # group by (engagement_range, axis)
    groups = defaultdict(list)
    for row in data:
        key = (float(row['engagement_range']), row['axis'])
        groups[key].append({
            'ttk': float(row['ttk_seconds']),
            'winner': row['winner'],
            'loser_health': float(row['loser_health'])
        })
        
    markdown_table = "| Range (m) | Axis | Avg TTK (s) | Win Rate (ShipA) | Win Rate (ShipB) | Draws/Timeouts |\n"
    markdown_table += "|-----------|------|-------------|------------------|------------------|----------------|\n"
    
    for key in sorted(groups.keys()):
        runs = groups[key]
        rnge, axis = key
        
        # Filter out timeouts for TTK average
        valid_ttks = [run['ttk'] for run in runs if run['winner'] in ("ShipA", "ShipB")]
        avg_ttk = statistics.mean(valid_ttks) if valid_ttks else 0.0
        std_ttk = statistics.stdev(valid_ttks) if len(valid_ttks) > 1 else 0.0
        
        ship_a_wins = sum(1 for run in runs if run['winner'] == 'ShipA')
        ship_b_wins = sum(1 for run in runs if run['winner'] == 'ShipB')
        draws = len(runs) - ship_a_wins - ship_b_wins
        
        a_win_rate = ship_a_wins / len(runs) * 100
        b_win_rate = ship_b_wins / len(runs) * 100
        
        markdown_table += f"| {rnge} | {axis} | {avg_ttk:.1f}s ±{std_ttk:.1f}s | {a_win_rate:.1f}% | {b_win_rate:.1f}% | {draws} |\n"
        
    return markdown_table

def main():
    print("Generating Tactical Analysis Report...")
    
    # Read Data
    missile_pd_data = read_csv('tactical_analysis/data/missile_vs_pd_results.csv')
    ttk_data = read_csv('tactical_analysis/data/time_to_kill_results.csv')
    
    # Generate snippets
    missile_pd_table = aggregate_missile_pd(missile_pd_data) if missile_pd_data else "*No data available*"
    ttk_table = aggregate_ttk(ttk_data) if ttk_data else "*No data available*"
    
    # Load Template
    template_path = 'tactical_analysis/templates/tactical_report_template.md'
    if not os.path.exists(template_path):
        print(f"Error: {template_path} not found.")
        return
        
    with open(template_path, 'r') as f:
        template_content = f.read()
        
    # Inject
    report_content = template_content.replace('{{MISSILE_VS_PD_TABLE}}', missile_pd_table)
    report_content = report_content.replace('{{TIME_TO_KILL_TABLE}}', ttk_table)
    
    # Save Report
    report_path = 'tactical_analysis/reports/latest_report.md'
    with open(report_path, 'w') as f:
        f.write(report_content)
        
    print(f"Report generated at {report_path}")

if __name__ == "__main__":
    main()
