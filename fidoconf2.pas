unit fidoconf2;

interface


{$ifdef __GPC__}
uses gpcstrings,gpcfidoconf;
{$endif}

{$ifdef fpc}
	{$ifdef linux}
    uses fidoconf,strings;
	{$endif}
{$endif}


{Improved getarea}
function Getareaimp(config:psfidoconfig; areaName:pchar):Psarea;

implementation

function Getareaimp(config:psfidoconfig; areaName:pchar):Psarea;
type
 area_array=array[1..100000] of sarea;
 Parea_array=^area_array;
var 
 a:psarea;
 aa:parea_array;
 i:integer;
 p:pointer;
begin
{Netmailarea?}
if stricomp(areaname,'netmailarea')=0 then begin
	getareaimp:=@config^.netmailarea;
    exit;
end;

if stricomp(areaname,config^.netmailarea.areaname)=0 then begin
	getareaimp:=@config^.netmailarea;
    exit;
end;

{normal area?}
a:=getarea(config,areaname);
if a=@config^.badarea then a:=nil;

{localarea}
if a=nil then begin
	{$ifdef __GPC__}
	aa:=parea_array(config^.localareas^);  
	{$else}
	aa:=addr(config^.localareas^);
	{$endif}
    for i:=1 to config^.localareacount do begin
		{$ifdef __GPC__}
		if stricomp(aa^[i].areaname,areaname)=0 then begin
			a:=@aa^[i];
            break;
        end;
		{$else}
		if stricomp(aa^[i].areaname,areaname)=0 then begin
			a:=@aa^[i];
            break;
        end;
		{$endif}
    end;
end;
getareaimp:=a;
end;

end.
