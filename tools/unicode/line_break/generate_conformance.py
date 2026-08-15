#!/usr/bin/env python3
"""Compile all 19,338 Unicode 17.0 LineBreakTest cases."""
from __future__ import annotations
import struct,sys
from pathlib import Path

def main():
 if len(sys.argv)!=3:raise SystemExit(f'usage: {Path(sys.argv[0]).name} LineBreakTest.txt output.bin')
 text=Path(sys.argv[1]).read_text(encoding='utf-8')
 if not text.startswith('# LineBreakTest-17.0.0.txt\n'):raise SystemExit('expected Unicode 17 LineBreakTest')
 cases=[]
 for no,line in enumerate(text.splitlines(),1):
  fields=line.split('#',1)[0].split()
  if not fields:continue
  if fields.pop(0)!='×':raise SystemExit(f'line {no}: expected initial no-break')
  cps=[];breaks=[False]
  while fields:
   if len(fields)<2:raise SystemExit(f'line {no}: incomplete pair')
   cp=int(fields.pop(0),16);mark=fields.pop(0)
   if mark not in ('×','÷'):raise SystemExit(f'line {no}: bad marker')
   if cp>0x10ffff or 0xd800<=cp<=0xdfff:raise SystemExit(f'line {no}: bad scalar')
   cps.append(cp);breaks.append(mark=='÷')
  if len(cps)>255:raise SystemExit(f'line {no}: too long')
  cases.append((cps,breaks))
 if len(cases)!=19338:raise SystemExit(f'expected 19338 cases, found {len(cases)}')
 out=bytearray(struct.pack('<4sBBBBI',b'CJLT',2,17,0,0,len(cases)))
 for cps,breaks in cases:
  out.append(len(cps));out.extend(bytes(breaks));out.extend(struct.pack(f'<{len(cps)}I',*cps))
 Path(sys.argv[2]).write_bytes(out)
if __name__=='__main__':main()
