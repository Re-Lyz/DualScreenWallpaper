using System;
using System.IO;
namespace Wallpaper {
 public static class ImageHeader {
  static int U16(byte[] b,int p,bool le) { return le ? b[p]|b[p+1]<<8 : b[p]<<8|b[p+1]; }
  static uint U32(byte[] b,int p,bool le) { return le ? (uint)(b[p]|b[p+1]<<8|b[p+2]<<16|b[p+3]<<24) : (uint)(b[p]<<24|b[p+1]<<16|b[p+2]<<8|b[p+3]); }
  static int Exif(byte[] b) {
   try {
    if(b.Length<14 || b[0]!=69 || b[1]!=120 || b[2]!=105 || b[3]!=102 || b[4]!=0 || b[5]!=0) return 0;
    bool le=b[6]==73 && b[7]==73;
    if(!le && !(b[6]==77 && b[7]==77)) return 0;
    if(U16(b,8,le)!=42) return 0;
    int p=checked(6+(int)U32(b,10,le));
    int n=U16(b,p,le); p+=2;
    for(int i=0;i<n;i++,p+=12) {
     if(U16(b,p,le)==274 && U16(b,p+2,le)==3 && U32(b,p+4,le)==1) return U16(b,p+8,le);
    }
   } catch(ArgumentException) {} catch(IndexOutOfRangeException) {} catch(OverflowException) {}
   return 0;
  }
  public static int[] Read(string path) {
   using(var s=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))
   using(var r=new BinaryReader(s)) {
    byte[] sig=r.ReadBytes(24);
    if(sig.Length==24 && sig[0]==137 && sig[1]==80 && sig[2]==78 && sig[3]==71 && sig[4]==13 && sig[5]==10 && sig[6]==26 && sig[7]==10 && sig[12]==73 && sig[13]==72 && sig[14]==68 && sig[15]==82) {
     int w=checked((int)U32(sig,16,false)), h=checked((int)U32(sig,20,false));
     if(w>0 && h>0) return new int[]{w,h,0};
     return null;
    }
    if(sig.Length<2 || sig[0]!=255 || sig[1]!=216) return null;
    s.Position=2; int width=0,height=0,orientation=0;
    while(s.Position<s.Length) {
     if(r.ReadByte()!=255) return null;
     byte marker; do { marker=r.ReadByte(); } while(marker==255);
     if(marker==217 || marker==218) break;
     if(marker==1 || (marker>=208 && marker<=215)) continue;
     int length=(r.ReadByte()<<8|r.ReadByte())-2;
     if(length<0 || s.Position+length>s.Length) return null;
     long next=s.Position+length;
     if(marker==225) { int value=Exif(r.ReadBytes(length)); if(value>0) orientation=value; }
     else if(marker>=192 && marker<=207 && marker!=196 && marker!=200 && marker!=204) {
      if(length<6) return null;
      r.ReadByte(); height=r.ReadByte()<<8|r.ReadByte(); width=r.ReadByte()<<8|r.ReadByte();
     }
     s.Position=next;
    }
    if(width<=0 || height<=0) return null;
    if(orientation>=5 && orientation<=8) { int t=width; width=height; height=t; }
    return new int[]{width,height,orientation};
   }
  }
 }
}
