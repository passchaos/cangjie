#!/usr/bin/env python3
"""Generate Unicode 17.0 UAX #14 properties with derived rule flags.

Usage:
    tools/unicode/line_break/generate_data.py \
        LineBreak.txt UnicodeData.txt EastAsianWidth.txt emoji-data.txt \
        src/unicode/line_break/data.bin

Each scalar is represented by a u16 before 256-scalar page deduplication:
bits 0..5 contain Line_Break, bits 6..8 contain the General_Category subset
needed by LB1/LB15/LB19/LB30b, bit 9 is $EastAsian, and bit 10 is
Extended_Pictographic.
"""
from __future__ import annotations
import re, struct, sys
from pathlib import Path

CLASSES=("BK","CR","LF","CM","NL","SG","WJ","ZW","GL","SP","ZWJ","B2","BA","BB","HY","CB","CL","CP","EX","IN","NS","OP","QU","IS","NU","PO","PR","SY","AI","AL","CJ","EB","EM","H2","H3","HL","ID","JL","JV","JT","RI","SA","AK","AP","AS","HH","VF","VI","XX")
CLASS={name:i for i,name in enumerate(CLASSES)}
GC={"Mn":1,"Mc":2,"Pi":3,"Pf":4,"Cn":5}
LIMIT=0x110000
RANGE=re.compile(r'^([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*([A-Za-z0-9_]+)')

def ranges(path):
 for no,line in enumerate(Path(path).read_text(encoding='utf-8').splitlines(),1):
  m=RANGE.match(line)
  if not m: continue
  a=int(m[1],16);b=int(m[2] or m[1],16)
  if a>b or b>=LIMIT: raise SystemExit(f'{path}:{no}: invalid range')
  yield a,b,m[3]

def flag(props,a,b,value):
 for cp in range(a,b+1): props[cp]|=value

def apply_unicode_data(props,path):
 first=None
 text=Path(path).read_text(encoding='utf-8')
 if not text.startswith('0000;<control>;Cc;'): raise SystemExit('unexpected UnicodeData input')
 for no,line in enumerate(text.splitlines(),1):
  f=line.split(';')
  if len(f)<3: raise SystemExit(f'{path}:{no}: malformed row')
  cp=int(f[0],16);name=f[1];cat=f[2]
  if name.endswith(', First>'): first=(cp,cat);continue
  if name.endswith(', Last>'):
   if first is None or first[1]!=cat: raise SystemExit(f'{path}:{no}: unmatched range')
   a=first[0];first=None
  else:a=cp
  value=GC.get(cat,0)<<6
  for x in range(a,cp+1):props[x]=(props[x]&~(7<<6))|value
 if first is not None:raise SystemExit(f'{path}: unterminated range')

def main():
 if len(sys.argv)!=6: raise SystemExit(f'usage: {Path(sys.argv[0]).name} LineBreak.txt UnicodeData.txt EastAsianWidth.txt emoji-data.txt output.bin')
 lb=Path(sys.argv[1]).read_text(encoding='utf-8')
 if not lb.startswith('# LineBreak-17.0.0.txt\n'):raise SystemExit('expected Unicode 17 LineBreak data')
 # UnicodeData omits unassigned scalars, so General_Category defaults to Cn.
 props=[CLASS['XX']|(GC['Cn']<<6)]*LIMIT
 for a,b,name in ranges(sys.argv[1]):
  if name not in CLASS:raise SystemExit(f'unknown Line_Break {name!r}')
  value=CLASS[name]
  for cp in range(a,b+1):props[cp]=(props[cp]&~0x3f)|value
 apply_unicode_data(props,sys.argv[2])
 eaw=Path(sys.argv[3]).read_text(encoding='utf-8')
 if not eaw.startswith('# EastAsianWidth-17.0.0.txt\n'):raise SystemExit('expected Unicode 17 EastAsianWidth data')
 for a,b,name in ranges(sys.argv[3]):
  if name in ('F','W','H'):flag(props,a,b,1<<9)
 emoji=Path(sys.argv[4]).read_text(encoding='utf-8')
 if '# Version: 17.0\n' not in emoji[:1024]:raise SystemExit('expected Unicode Emoji 17 data')
 for a,b,name in ranges(sys.argv[4]):
  if name=='Extended_Pictographic':flag(props,a,b,1<<10)
 pages=[];slots={};index=[]
 for off in range(0,LIMIT,256):
  page=struct.pack('<256H',*props[off:off+256]);slot=slots.get(page)
  if slot is None:slot=len(pages);slots[page]=slot;pages.append(page)
  index.append(slot)
 if len(pages)>0xffff:raise SystemExit('too many pages')
 out=bytearray(struct.pack('<4sBBBBHH',b'CJL2',2,17,0,0,len(index),len(pages)))
 out.extend(struct.pack(f'<{len(index)}H',*index));out.extend(b''.join(pages));Path(sys.argv[5]).write_bytes(out)
if __name__=='__main__':main()
