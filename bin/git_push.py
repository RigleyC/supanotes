import subprocess

def run(cmd):
    print(f"Running: {cmd}")
    try:
        result = subprocess.run(cmd, shell=True, text=True, capture_output=True, timeout=10)
        print(f"STDOUT: {result.stdout}")
        print(f"STDERR: {result.stderr}")
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        print("TIMEOUT!")
        return False

run('git add .')
run('git commit -m "fix(notes): restore missing notes and fix task node excerpt filtering"')
run('git push origin HEAD')
