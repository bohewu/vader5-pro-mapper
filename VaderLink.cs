using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public sealed class VaderLink : IDisposable {
 [StructLayout(LayoutKind.Sequential)] public struct XPad { public ushort Buttons; public byte LT,RT; public short LX,LY,RX,RY; }
 [StructLayout(LayoutKind.Sequential)] public struct XState { public uint Packet; public XPad Pad; }
 [DllImport("xinput1_4.dll")] static extern uint XInputGetState(uint index,out XState state);
 public sealed class InputView { public bool Connected; public int Slot=-1; public string Pressed=""; public bool R3,M1; public short LX,LY,RX,RY; public byte LT,RT; }
 public static InputView GameOutput(){
  for(uint slot=0;slot<4;slot++){XState s;if(XInputGetState(slot,out s)!=0)continue;var v=new InputView{Connected=true,Slot=(int)slot,R3=(s.Pad.Buttons&0x80)!=0,LX=s.Pad.LX,LY=s.Pad.LY,RX=s.Pad.RX,RY=s.Pad.RY,LT=s.Pad.LT,RT=s.Pad.RT};
   var names=new List<string>();ushort[] masks={1,2,4,8,0x10,0x20,0x40,0x80,0x100,0x200,0x1000,0x2000,0x4000,0x8000};string[] labels={"Up","Down","Left","Right","Menu","View","L3","R3","LB","RB","A","B","X","Y"};for(int i=0;i<masks.Length;i++)if((s.Pad.Buttons&masks[i])!=0)names.Add(labels[i]);v.Pressed=string.Join(", ",names);return v;
  }return new InputView();
 }
 public static InputView RawInput(byte[] report){
  if(report==null||report.Length<29||report[0]!=0x5A||report[1]!=0xA5||report[2]!=0xEF)return null;
  var v=new InputView{Connected=true,R3=(report[12]&0x80)!=0,M1=(report[13]&4)!=0,LX=BitConverter.ToInt16(report,3),LY=BitConverter.ToInt16(report,5),RX=BitConverter.ToInt16(report,7),RY=BitConverter.ToInt16(report,9),LT=report[15],RT=report[16]};
  var names=new List<string>();string[][] labels={new[]{"Up","Right","Down","Left","A","B","View","X"},new[]{"Y","Menu","LB","RB","LT","RT","L3","R3"},new[]{"C","Z","M1","M2","M3","M4","LM","RM"}};for(int b=0;b<3;b++)for(int bit=0;bit<8;bit++)if((report[11+b]&(1<<bit))!=0)names.Add(labels[b][bit]);if((report[14]&1)!=0)names.Add("Fn");if((report[14]&2)!=0)names.Add("Turbo");if((report[14]&8)!=0)names.Add("Home");v.Pressed=string.Join(", ",names);return v;
 }
 const string Dll = "hidapi.dll";
 static VaderLink(){
  NativeLibrary.SetDllImportResolver(typeof(VaderLink).Assembly,(name,assembly,searchPath)=>{
   if(name!=Dll)return IntPtr.Zero;
   string configured=Environment.GetEnvironmentVariable("VADER_HIDAPI_PATH");
   string library=string.IsNullOrWhiteSpace(configured)?Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"Flydigi Space Station","hidapi.dll"):Path.GetFullPath(configured);
   if(!File.Exists(library))throw new DllNotFoundException("Install Flydigi Space Station or set VADER_HIDAPI_PATH to its existing hidapi.dll.");
   return NativeLibrary.Load(library);
  });
 }
 [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] static extern int hid_init();
 [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr hid_version_str();
 [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr hid_open_path([MarshalAs(UnmanagedType.LPUTF8Str)]string path);
 [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] static extern int hid_write(IntPtr dev,byte[] data,UIntPtr size);
 [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] static extern int hid_read_timeout(IntPtr dev,byte[] data,UIntPtr size,int ms);
 [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr hid_error(IntPtr dev);
 [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] static extern void hid_close(IntPtr dev);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
 [DllImport("hid.dll",SetLastError=true)] static extern bool HidD_GetPreparsedData(SafeFileHandle dev,out IntPtr data);
 [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr data);
 [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr data,IntPtr caps);
 IntPtr device;
 public byte ReportId {get;set;}
 public static string Version {get {return Marshal.PtrToStringAnsi(hid_version_str());}}
 public static string Caps(string path) {
  using(var f=CreateFile(path,0,3,IntPtr.Zero,3,0,IntPtr.Zero)){
   if(f.IsInvalid)throw new IOException("HID descriptor open error "+Marshal.GetLastWin32Error());
   IntPtr pp;if(!HidD_GetPreparsedData(f,out pp))throw new IOException("HID descriptor error");
   IntPtr c=Marshal.AllocHGlobal(64);
   try{int rc=HidP_GetCaps(pp,c);return "CapsHR="+rc.ToString("X8")+" usage="+((ushort)Marshal.ReadInt16(c,0)).ToString("X4")+" usagePage="+((ushort)Marshal.ReadInt16(c,2)).ToString("X4")+" inputBytes="+Marshal.ReadInt16(c,4)+" outputBytes="+Marshal.ReadInt16(c,6)+" featureBytes="+Marshal.ReadInt16(c,8);}
   finally{Marshal.FreeHGlobal(c);HidD_FreePreparsedData(pp);}
  }
 }
 public VaderLink(string path,byte reportId=0){hid_init();ReportId=reportId;device=hid_open_path(path);if(device==IntPtr.Zero)throw new IOException("hid_open_path: "+Marshal.PtrToStringUni(hid_error(IntPtr.Zero)));}
 public void Dispose(){if(device!=IntPtr.Zero){hid_close(device);device=IntPtr.Zero;}}
 static readonly HashSet<byte> Allowed=new HashSet<byte>{0x01,0x02,0x03,0x04,0x10,0x11,0x13,0xA1,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7,0xAC};
 public void Write(byte command,params byte[] payload){
  if(!Allowed.Contains(command))throw new InvalidOperationException("Command not allowed: "+command.ToString("X2"));
  if(command==0x13&&(payload.Length!=2||payload[0]!=4||payload[1]>1))throw new InvalidOperationException("Only the Turbo master switch may be changed");
  if(payload.Length>27)throw new ArgumentException("Payload too large");
  byte[] data=new byte[33];data[0]=ReportId;data[1]=0x5A;data[2]=0xA5;data[3]=command;data[4]=(byte)(2+payload.Length);Array.Copy(payload,0,data,5,payload.Length);
  int sum=0;for(int i=3;i<5+payload.Length;i++)sum+=data[i];data[5+payload.Length]=(byte)sum;
  int n=hid_write(device,data,(UIntPtr)data.Length);if(n<0)throw new IOException("HID write "+command.ToString("X2")+": "+Marshal.PtrToStringUni(hid_error(device)));
 }
 public byte[] Read(int ms){byte[] b=new byte[65];int n=hid_read_timeout(device,b,(UIntPtr)b.Length,ms);if(n<0)throw new IOException("HID read: "+Marshal.PtrToStringUni(hid_error(device)));if(n==0)return null;int offset=(n>2&&b[0]==0x5A&&b[1]==0xA5)?0:(n>3&&b[1]==0x5A&&b[2]==0xA5)?1:-1;if(offset<0)return null;byte[] frame=new byte[n-offset];Array.Copy(b,offset,frame,0,frame.Length);return frame;}
 public void Drain(){for(int i=0;i<512;i++)if(Read(0)==null)break;}
 public byte[] Request(byte command,params byte[] payload){Drain();Write(command,payload);var end=DateTime.UtcNow.AddMilliseconds(command==0xA6?10000:1800);while(DateTime.UtcNow<end){var b=Read(100);if(b!=null&&b.Length>=32&&b[2]==command){int sum=0;for(int i=2;i<31;i++)sum+=b[i];if((byte)sum!=b[31])throw new IOException("Reply checksum failed");return b;}}throw new TimeoutException("No reply for "+command.ToString("X2")+", reportId="+ReportId);}
 public byte[] WriteMapping(byte profile,byte[] bytes){
  if(profile>3||bytes.Length!=840||bytes[0]!=2||bytes[1]!=3)throw new ArgumentException("Only PC profiles and layout 3.2 are writable");
  if(Request(0xA1)[5]!=profile)throw new InvalidOperationException("The intended profile must already be active");
  Request(0xA4,profile,0,42,20);
  for(int index=0;index<42;index++){byte[] payload=new byte[21];payload[0]=(byte)index;Array.Copy(bytes,index*20,payload,1,20);Request(0xA5,payload);}
  Request(0xA6,bytes[225],bytes[226]);System.Threading.Thread.Sleep(250);
  var after=ReadBlob(0xA3,profile);if(after.Length!=bytes.Length)throw new IOException("Written mapping length mismatch");for(int i=0;i<after.Length;i++)if(after[i]!=bytes[i])throw new IOException("Written mapping differs at "+i);return after;
 }
 public byte[] ReadBlob(byte command,byte profile){
  if(command!=0xA3&&command!=0xA7&&command!=0xAC)throw new ArgumentException("Not a read blob command");
  Drain();Write(command,profile,20);var parts=new Dictionary<int,byte[]>();int total=0;var end=DateTime.UtcNow.AddSeconds(4);
  while(DateTime.UtcNow<end){var r=Read(100);if(r==null||r.Length<32||r[2]!=command||r[5]!=profile)continue;int sum=0;for(int i=2;i<31;i++)sum+=r[i];if((byte)sum!=r[31])throw new IOException("Blob checksum failed");if(total==0)total=r[3];if(total==0||r[3]!=total||r[4]>=total)throw new IOException("Bad blob header");byte[] chunk=new byte[20];Array.Copy(r,6,chunk,0,20);parts[r[4]]=chunk;if(parts.Count==total){byte[] blob=new byte[20*total];for(int i=0;i<total;i++)Array.Copy(parts[i],0,blob,20*i,20);return blob;}}
  throw new TimeoutException("Incomplete blob "+command.ToString("X2")+" "+parts.Count+"/"+total);
 }
}
