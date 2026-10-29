"""Native stderr is logging, not a PowerShell terminating error."""
from pathlib import Path
import subprocess, sys
ROOT=Path(__file__).resolve().parents[2]
def run(command, log):
 with open(log,'w',encoding='utf-8') as output:
  process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',bufsize=1)
  for line in process.stdout:
   output.write(line); output.flush()
   print(line,end='',flush=True)
  return process.wait()
if __name__=='__main__':
 sys.exit(run([sys.executable,'-u',str(Path(__file__).with_name('prepare.py'))],ROOT/'.model-prep/last-run.log'))
