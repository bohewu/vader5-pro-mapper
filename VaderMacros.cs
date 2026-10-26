using System;
using System.IO;
using System.Text;
using System.Collections.Generic;

// Protocol reference: OpenVader docs/PROTOCOL.md (see README). No vendor binary is bundled.
public sealed class VaderMacroStep {
 public int Time {get;set;}
 public byte Key {get;set;}
 public byte Event {get;set;}
 public VaderMacroStep Clone(){return new VaderMacroStep{Time=Time,Key=Key,Event=Event};}
}
public sealed class VaderMacro {
 public byte Trigger {get;set;}
 public string Name {get;set;}="";
 public byte Playback {get;set;}=1;
 public int RepeatInterval {get;set;}
 public List<VaderMacroStep> Steps {get;set;}=new List<VaderMacroStep>();
 internal byte[] OriginalRecord;
 internal string OriginalSignature;
 internal string Signature(){
  var s=new StringBuilder();s.Append(Trigger).Append('|').Append(Convert.ToBase64String(Encoding.UTF8.GetBytes(Name??""))).Append('|').Append(Playback).Append('|').Append(RepeatInterval);
  foreach(var step in Steps)s.Append('|').Append(step.Time).Append(',').Append(step.Key).Append(',').Append(step.Event);
  return s.ToString();
 }
 public VaderMacro Clone(){var m=new VaderMacro{Trigger=Trigger,Name=Name,Playback=Playback,RepeatInterval=RepeatInterval,OriginalRecord=OriginalRecord==null?null:(byte[])OriginalRecord.Clone(),OriginalSignature=OriginalSignature};foreach(var s in Steps)m.Steps.Add(s.Clone());return m;}
 public bool Unchanged {get{return OriginalRecord!=null&&OriginalSignature==Signature();}}
}
public sealed class VaderMacroStore {
 public const int Size=1660, Capacity=1632, MaxMacros=10, MaxSteps=256;
 readonly byte[] original;
 readonly string[] signatures;
 public List<VaderMacro> Macros {get;private set;}=new List<VaderMacro>();
 static int U16(byte[] b,int p){return b[p]|b[p+1]<<8;}
 static void Put16(byte[] b,int p,int n){b[p]=(byte)n;b[p+1]=(byte)(n>>8);}
 public VaderMacroStore(byte[] bytes){
  if(bytes==null||bytes.Length!=Size)throw new InvalidDataException("巨集儲存區必須為 1660 位元組。");
  original=(byte[])bytes.Clone();int version=U16(bytes,0),count=U16(bytes,2);
  if((version!=0x0100&&version!=0xFFFF)||(count>MaxMacros&&count!=0xFFFF))throw new InvalidDataException("不支援此巨集格式；不會覆寫。");
  if(count==0xFFFF)count=0;
  var triggers=new HashSet<byte>();var ranges=new List<Tuple<int,int>>();
  for(int i=0;i<count;i++){
   int start=24+U16(bytes,4+2*i)*4;
   if(start<24||start+32>Size-4)throw new InvalidDataException("巨集索引超出儲存區。");
   int steps=U16(bytes,start+1),end=start+32+steps*4;
   if(steps<1||steps>MaxSteps||end>Size-4)throw new InvalidDataException("巨集步驟數或長度無效。");
   foreach(var r in ranges)if(start<r.Item2&&end>r.Item1)throw new InvalidDataException("巨集記錄重疊。");
   ranges.Add(Tuple.Create(start,end));
   if(bytes[start]>23||!triggers.Add(bytes[start]))throw new InvalidDataException("巨集觸發鍵不支援或重複。");
   int nameEnd=start+12;while(nameEnd<start+32&&bytes[nameEnd]!=0&&bytes[nameEnd]!=255)nameEnd++;
   var m=new VaderMacro{Trigger=bytes[start],Name=new UTF8Encoding(false,true).GetString(bytes,start+12,nameEnd-start-12),Playback=bytes[start+3],RepeatInterval=U16(bytes,start+4)};
   for(int k=0;k<steps;k++){int p=start+32+4*k;m.Steps.Add(new VaderMacroStep{Time=U16(bytes,p),Key=bytes[p+2],Event=bytes[p+3]});}
   m.OriginalRecord=new byte[end-start];Array.Copy(bytes,start,m.OriginalRecord,0,end-start);m.OriginalSignature=m.Signature();Macros.Add(m);
  }
  signatures=new string[Macros.Count];for(int i=0;i<Macros.Count;i++)signatures[i]=Macros[i].Signature();
 }
 public static void Validate(VaderMacro m){
  if(m==null||m.Trigger>23)throw new ArgumentException("請選擇有效的觸發鍵。");
  if(m.Playback<1||m.Playback>3)throw new ArgumentException("請選擇單次、按住重複或切換重複。");
  if(m.RepeatInterval<0||m.RepeatInterval>65534)throw new ArgumentException("重複間隔必須為 0～65534 ms。");
  if(Encoding.UTF8.GetByteCount(m.Name??"")>20||(m.Name??"").IndexOf('\0')>=0)throw new ArgumentException("巨集名稱最多 20 個 UTF-8 位元組（中文字通常每字 3 個）。");
  if(m.Steps==null||m.Steps.Count<1||m.Steps.Count>MaxSteps)throw new ArgumentException("每組巨集需要 1～256 個步驟。");
  int previous=0;var held=new HashSet<byte>();
  foreach(var step in m.Steps){
   if(step.Time<previous||step.Time>65535)throw new ArgumentException("巨集時間必須依序增加，總長不超過 65535 ms。");
   if(step.Key>15||step.Event>1)throw new ArgumentException("巨集只支援一般遊戲按鍵的按下與放開。");
   if(step.Event==1){if(!held.Add(step.Key))throw new ArgumentException("同一按鍵再次按下前，請先加入放開步驟。");}
   else if(!held.Remove(step.Key))throw new ArgumentException("放開步驟前必須先有對應的按下步驟。");
   previous=step.Time;
  }
  if(held.Count>0)throw new ArgumentException("巨集結束前，請放開所有已按下的按鍵。");
 }
 public static int BytesUsed(VaderMacro[] macros){int used=0;foreach(var m in macros)used+=32+m.Steps.Count*4;return used;}
 public byte[] Encode(VaderMacro[] macros){
  if(macros==null||macros.Length>MaxMacros)throw new ArgumentException("每個配置最多 10 組巨集。");
  var seen=new HashSet<byte>();bool same=macros.Length==signatures.Length;
  for(int i=0;i<macros.Length;i++){
   var m=macros[i];if(m==null||!seen.Add(m.Trigger))throw new ArgumentException("同一觸發鍵只能設定一組巨集。");
   if(!m.Unchanged)Validate(m);
   if(i>=signatures.Length||m.Signature()!=signatures[i])same=false;
  }
  if(same)return (byte[])original.Clone();
  if(BytesUsed(macros)>Capacity)throw new ArgumentException("巨集超過板載容量，請減少步驟或巨集數量。");
  byte[] result=(byte[])original.Clone();Array.Fill<byte>(result,255,24,Capacity);Put16(result,0,0x0100);Put16(result,2,macros.Length);
  for(int i=0;i<10;i++)Put16(result,4+2*i,0);
  int pos=24;
  for(int i=0;i<macros.Length;i++){
   var m=macros[i];Put16(result,4+2*i,(pos-24)/4);
   if(m.Unchanged){Array.Copy(m.OriginalRecord,0,result,pos,m.OriginalRecord.Length);pos+=m.OriginalRecord.Length;continue;}
   // Retain reserved header bytes when editing an existing record.
   if(m.OriginalRecord!=null)Array.Copy(m.OriginalRecord,0,result,pos,32);
   result[pos]=m.Trigger;Put16(result,pos+1,m.Steps.Count);result[pos+3]=m.Playback;Put16(result,pos+4,m.RepeatInterval);
   Array.Clear(result,pos+12,20);byte[] name=Encoding.UTF8.GetBytes(m.Name??"");Array.Copy(name,0,result,pos+12,name.Length);
   for(int k=0;k<m.Steps.Count;k++){var s=m.Steps[k];int p=pos+32+4*k;Put16(result,p,s.Time);result[p+2]=s.Key;result[p+3]=s.Event;}
   pos+=32+m.Steps.Count*4;
  }
  return result;
 }
 public byte[] UpdateMapping(byte[] mapping,VaderMacro[] macros){
  if(mapping==null||mapping.Length!=840||mapping[0]!=2||mapping[1]!=3)throw new ArgumentException("僅支援配置格式 3.2。");
  byte[] result=(byte[])mapping.Clone();var remaining=new HashSet<byte>();foreach(var m in macros)remaining.Add(m.Trigger);
  foreach(var old in Macros){int p=13+3*old.Trigger;if(!remaining.Contains(old.Trigger)&&result[p]==32){result[p]=255;result[p+1]=0;result[p+2]=0;}}
  foreach(var m in macros)if(!m.Unchanged){int p=13+3*m.Trigger;result[p]=32;result[p+1]=0;result[p+2]=0;}
  return result;
 }
}
