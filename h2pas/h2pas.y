%{
program h2pas;

(*
    $Id$
    Copyright (c) 1993-98 by Florian Klaempfl

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************)



  uses
   {$ifdef go32v2}
   {$ifndef NOEXCP}
   dpmiexcp,
   {$endif NOEXCP}
   {$endif}
   {$IFDEF WIN32}
   SysUtils,
   {$else}
   strings,
   {$endif}
   options,scan,converu,lexlib,yacclib;

  type
     YYSTYPE = presobject;

  const
     INT_STR = 'longint';
     UINT_STR = 'cardinal';
     SHORT_STR = 'integer';
     USHORT_STR = 'word';
     CHAR_STR = 'char';
     { should we use byte or char for 'unsigned char' ?? }
     UCHAR_STR = 'byte';
     REAL_STR = 'real';

  var
     debug : boolean;
     hp,ph : presobject;
     extfile: text;  (* file for implementation headers extern procs *)
     IsExtern:boolean;
     must_write_packed_field : boolean;
     tempfile : text;
     No_pop:boolean;
     s,TN,PN : String;

(* $ define yydebug
 compile with -dYYDEBUG to get debugging info *)

  const
     (* number of a?b:c construction in one define *)
     if_nb : longint = 0;
     is_packed : boolean = false;
     is_procvar : boolean = false;

  var space_array : array [0..255] of byte;
      space_index : byte;

        procedure shift(space_number : byte);
          var
             i : byte;
          begin
             space_array[space_index]:=space_number;
             inc(space_index);
             for i:=1 to space_number do
               aktspace:=aktspace+' ';
          end;

        procedure popshift;
          begin
             dec(space_index);
             if space_index<0 then
               internalerror(20);
             dec(byte(aktspace[0]),space_array[space_index]);
          end;

    function str(i : longint) : string;
      var
         s : string;
      begin
         system.str(i,s);
         str:=s;
      end;

    function hexstr(i : cardinal) : string;

    const
      HexTbl : array[0..15] of char='0123456789ABCDEF';
    var
      str : string;
    begin
      str:='';
      while i<>0 do
        begin
           str:=hextbl[i and $F]+str;
           i:=i shr 4;
        end;
      if str='' then str:='0';
      hexstr:='$'+str;
    end;

    function uppercase(s : string) : string;
      var
         i : byte;
      begin
         for i:=1 to length(s) do
           s[i]:=UpCase(s[i]);
         uppercase:=s;
      end;

    procedure write_type_specifier(var outfile:text; p : presobject);forward;
    procedure write_p_a_def(var outfile:text; p,simple_type : presobject);forward;
    procedure write_ifexpr(var outfile:text; p : presobject);forward;
    procedure write_funexpr(var outfile:text; p : presobject);forward;

    procedure yymsg(const msg : string);
      begin
         writeln('line ',line_no,': ',msg);
      end;

    procedure write_packed_fields_info(var outfile:text; p : presobject; ph : string);

      var
         hp1,hp2,hp3 : presobject;
         is_sized : boolean;
         line : string;
         flag_index : longint;
         name : pchar;
         ps : byte;

      begin
         { write out the tempfile created }
         close(tempfile);
         reset(tempfile);
         is_sized:=false;
         flag_index:=0;
         writeln(outfile,aktspace,'const');
         shift(3);
         while not eof(tempfile) do
           begin
              readln(tempfile,line);
              ps:=pos('&',line);
              if ps>0 then
                line:=copy(line,1,ps-1)+ph+'_'+copy(line,ps+1,255);
              writeln(outfile,aktspace,line);
           end;
         close(tempfile);
         rewrite(tempfile);
         popshift;
         (* walk through all members *)
         hp1 := p^.p1;
         while assigned(hp1) do
           begin
              (* hp2 is t_memberdec *)
              hp2:=hp1^.p1;
              (*  hp3 is t_declist *)
              hp3:=hp2^.p2;
              while assigned(hp3) do
                begin
                   if assigned(hp3^.p1^.p3) and
                      (hp3^.p1^.p3^.typ = t_size_specifier) then
                     begin
                        is_sized:=true;
                        name:=hp3^.p1^.p2^.p;
                        { get function in interface }
                        write(outfile,aktspace,'function ',name);
                        write(outfile,'(var a : ',ph,') : ');
                        shift(2);
                        write_p_a_def(outfile,hp3^.p1^.p1,hp2^.p1);
                        writeln(outfile,';');
                        popshift;
                        { get function in implementation }
                        write(extfile,aktspace,'function ',name);
                        write(extfile,'(var a : ',ph,') : ');
                        shift(2);
                        write_p_a_def(extfile,hp3^.p1^.p1,hp2^.p1);
                        writeln(extfile,';');
                        writeln(extfile,aktspace,'begin');
                        shift(3);
                        write(extfile,aktspace,name,':=(a.flag',flag_index);
                        writeln(extfile,' and bm_',ph,'_',name,') shr bp_',ph,'_',name,';');
                        popshift;
                        writeln(extfile,aktspace,'end;');
                        popshift;
                        writeln(extfile);
                        { set function in interface }
                        write(outfile,aktspace,'procedure set_',name);
                        write(outfile,'(var a : ',ph,'; __',name,' : ');
                        shift(2);
                        write_p_a_def(outfile,hp3^.p1^.p1,hp2^.p1);
                        writeln(outfile,');');
                        popshift;
                        { set function in implementation }
                        write(extfile,aktspace,'procedure set_',name);
                        write(extfile,'(var a : ',ph,'; __',name,' : ');
                        shift(2);
                        write_p_a_def(extfile,hp3^.p1^.p1,hp2^.p1);
                        writeln(extfile,');');
                        writeln(extfile,aktspace,'begin');
                        shift(3);
                        write(extfile,aktspace,'a.flag',flag_index,':=');
                        write(extfile,'a.flag',flag_index,' or ');
                        writeln(extfile,'((__',name,' shl bp_',ph,'_',name,') and bm_',ph,'_',name,');');
                        popshift;
                        writeln(extfile,aktspace,'end;');
                        popshift;
                        writeln(extfile);
                     end
                   else if is_sized then
                     begin
                        is_sized:=false;
                        inc(flag_index);
                     end;
                   hp3:=hp3^.next;
                end;
              hp1:=hp1^.next;
           end;
         must_write_packed_field:=false;
         block_type:=bt_no;
      end;

    procedure write_expr(var outfile:text; p : presobject);
      begin
      if assigned(p) then
        begin
         case p^.typ of
            t_id,t_ifexpr : write(outfile,p^.p);
            t_funexprlist : write_funexpr(outfile,p);
            t_preop : begin
                         write(outfile,p^.p,'(');
                         write_expr(outfile,p^.p1);
                         write(outfile,')');
                         flush(outfile);
                      end;
            t_typespec : begin
                         write_type_specifier(outfile,p^.p1);
                         write(outfile,'(');
                         write_expr(outfile,p^.p2);
                         write(outfile,')');
                         flush(outfile);
                      end;
            t_bop : begin
                       if p^.p1^.typ<>t_id then
                         write(outfile,'(');
                       write_expr(outfile,p^.p1);
                       if p^.p1^.typ<>t_id then
                       write(outfile,')');
                       write(outfile,p^.p);
                       if p^.p2^.typ<>t_id then
                         write(outfile,'(');
                       write_expr(outfile,p^.p2);
                       if p^.p2^.typ<>t_id then
                         write(outfile,')');
                    flush(outfile);
                    end;
            else internalerror(2);
            end;
         end;
      end;

    procedure write_ifexpr(var outfile:text; p : presobject);
      begin
         flush(outfile);
         write(outfile,'if ');
         write_expr(outfile,p^.p1);
         writeln(outfile,' then');
         write(outfile,aktspace,'  ');
         write(outfile,p^.p);
         write(outfile,':=');
         write_expr(outfile,p^.p2);
         writeln(outfile);
         writeln(outfile,aktspace,'else');
         write(outfile,aktspace,'  ');
         write(outfile,p^.p);
         write(outfile,':=');
         write_expr(outfile,p^.p3);
         writeln(outfile,';');
         write(outfile,aktspace);
         flush(outfile);
      end;

    procedure write_all_ifexpr(var outfile:text; p : presobject);
      begin
      if assigned(p) then
        begin
           case p^.typ of
             t_id :;
             t_preop :
               write_all_ifexpr(outfile,p^.p1);
             t_bop :
               begin
                  write_all_ifexpr(outfile,p^.p1);
                  write_all_ifexpr(outfile,p^.p2);
               end;
             t_ifexpr :
               begin
                  write_all_ifexpr(outfile,p^.p1);
                  write_all_ifexpr(outfile,p^.p2);
                  write_all_ifexpr(outfile,p^.p3);
                  write_ifexpr(outfile,p);
               end;
             t_typespec :
                  write_all_ifexpr(outfile,p^.p2);
             t_funexprlist,
             t_exprlist :
               begin
                 if assigned(p^.p1) then
                   write_all_ifexpr(outfile,p^.p1);
                 if assigned(p^.next) then
                   write_all_ifexpr(outfile,p^.next);
               end
             else
               internalerror(6);
           end;
        end;
      end;

    procedure write_funexpr(var outfile:text; p : presobject);
      var
         i : longint;

      begin
      if assigned(p) then
        begin
           case p^.typ of
             t_ifexpr :
               write(outfile,p^.p);
             t_exprlist :
               begin
                  write_expr(outfile,p^.p1);
                  if assigned(p^.next) then
                    begin
                      write(outfile,',');
                      write_funexpr(outfile,p^.next);
                    end
               end;
             t_funcname :
               begin
                  shift(2);
                  if if_nb>0 then
                    begin
                       writeln(outfile,aktspace,'var');
                       write(outfile,aktspace,'   ');
                       for i:=1 to if_nb do
                         begin
                            write(outfile,'if_local',i);
                            if i<if_nb then
                              write(outfile,', ')
                            else
                              writeln(outfile,' : longint;');
                         end;
                       writeln(outfile,aktspace,'(* result types are not known *)');
                       if_nb:=0;
                    end;
                  writeln(outfile,aktspace,'begin');
                  shift(3);
                  write(outfile,aktspace);
                  write_all_ifexpr(outfile,p^.p2);
                  write_expr(outfile,p^.p1);
                  write(outfile,':=');
                  write_funexpr(outfile,p^.p2);
                  writeln(outfile,';');
                  popshift;
                  writeln(outfile,aktspace,'end;');
                  popshift;
                  flush(outfile);
               end;
             t_funexprlist :
               begin
                  if assigned(p^.p3) then
                    begin
                       write_type_specifier(outfile,p^.p3);
                       write(outfile,'(');
                    end;
                  if assigned(p^.p1) then
                    write_funexpr(outfile,p^.p1);
                  if assigned(p^.p2) then
                    begin
                      write(outfile,'(');
                      write_funexpr(outfile,p^.p2);
                      write(outfile,')');
                    end;
                  if assigned(p^.p3) then
                    write(outfile,')');
               end
             else internalerror(5);
           end;
        end;
      end;

     function ellipsisarg : presobject;
       begin
          ellipsisarg:=new(presobject,init_two(t_arg,nil,nil));
       end;

    const
       (* if in args *dname is replaced by pdname *)
       in_args : boolean = false;
       typedef_level : longint = 0;

    (* writes an argument list, where p is t_arglist *)

    procedure write_args(var outfile:text; p : presobject);
      var
         length,para : longint;
         old_in_args : boolean;
         varpara : boolean;

      begin
         para:=1;
         length:=0;
         old_in_args:=in_args;
         in_args:=true;
         write(outfile,'(');
         shift(2);

         (* walk through all arguments *)
         (* p must be of type t_arglist *)
         while assigned(p) do
           begin
              if p^.typ<>t_arglist then
                internalerror(10);
              (* is ellipsis ? *)
              if not assigned(p^.p1^.p1) and
                 not assigned(p^.p1^.next) then
                begin
                   { write(outfile,'...'); }
                   write(outfile,'args:array of const');
                   { if variable number of args we must allways pop }
                   no_pop:=false;
                end
              (* we need to correct this in the pp file after *)
              else
                begin
                   (* generate a call by reference parameter ?       *)
                   varpara:=usevarparas and assigned(p^.p1^.p2^.p1) and
                     ((p^.p1^.p2^.p1^.typ=t_pointerdef) or
                     (p^.p1^.p2^.p1^.typ=t_addrdef));
                   (* do not do it for char pointer !!               *)
                   (* para : pchar; and var para : char; are         *)
                   (* completely different in pascal                 *)
                   (* here we exclude all typename containing char   *)
                   (* is this a good method ??                       *)


                   if varpara and
                      (p^.p1^.p2^.p1^.typ=t_pointerdef) and
                      (p^.p1^.p2^.p1^.p1^.typ=t_id) and
                     (pos('CHAR',uppercase(p^.p1^.p2^.p1^.p1^.str))<>0) then
                     varpara:=false;
                   if varpara then
                     begin
                        write(outfile,'var ');
                        length:=length+4;
                     end;

                   (* write new type name *)
                   if assigned(p^.p1^.p2^.p2) then
                     begin
                        write(outfile,p^.p1^.p2^.p2^.p);
                        length:=length+p^.p1^.p2^.p2^.strlength;
                     end
                   else
                     begin
                        write(outfile,'_para',para);
                        { not exact but unimportant }
                        length:=length+6;
                     end;
                   write(outfile,':');
                   if varpara then
                     write_p_a_def(outfile,p^.p1^.p2^.p1^.p1,p^.p1^.p1)
                   else
                     write_p_a_def(outfile,p^.p1^.p2^.p1,p^.p1^.p1);

                end;
              p:=p^.next;
              if assigned(p) then
                begin
                   write(outfile,'; ');
                   { if length>40 then : too complicated to compute }
                   if (para mod 5) = 0 then
                     begin
                        writeln(outfile);
                        write(outfile,aktspace);
                     end;
                end;
              inc(para);
           end;
         write(outfile,')');
         flush(outfile);
         in_args:=old_in_args;
         popshift;
      end;

    procedure write_p_a_def(var outfile:text; p,simple_type : presobject);
      var
         i : longint;
         error : integer;
         constant : boolean;

      begin
         if not(assigned(p)) then
           begin
              write_type_specifier(outfile,simple_type);
              exit;
           end;
         case p^.typ of
            t_pointerdef : begin
                              (* procedure variable ? *)
                              if assigned(p^.p1) and (p^.p1^.typ=t_procdef) then
                                begin
                                   is_procvar:=true;
                                   (* distinguish between procedure and function *)
                                   if (simple_type^.typ=t_void) and (p^.p1^.p1=nil) then
                                     begin
                                        write(outfile,'procedure ');

                                        shift(10);
                                        (* write arguments *)
                                        if assigned(p^.p1^.p2) then
                                          write_args(outfile,p^.p1^.p2);
                                        flush(outfile);
                                        popshift;
                                     end
                                   else
                                     begin
                                        write(outfile,'function ');
                                        shift(9);
                                        (* write arguments *)
                                        if assigned(p^.p1^.p2) then
                                          write_args(outfile,p^.p1^.p2);
                                        write(outfile,':');
                                        flush(outfile);
                                        write_p_a_def(outfile,p^.p1^.p1,simple_type);
                                        popshift;
                                     end
                                end
                              else
                                begin
                                   (* generate "pointer" ? *)
                                   if (simple_type^.typ=t_void) and (p^.p1=nil) then
                                      begin
                                       write(outfile,'pointer');
                                       flush(outfile);
                                      end
                                   else
                                     begin
                                        if in_args then
                                          write(outfile,'p')
                                        else
                                          write(outfile,'^');
                                        flush(outfile);
                                        write_p_a_def(outfile,p^.p1,simple_type);
                                     end;
                                end;
                           end;
            t_arraydef : begin
                             constant:=false;
                             if p^.p2^.typ=t_id then
                               begin
                                  val(p^.p2^.str,i,error);
                                  if error=0 then
                                    begin
                                       dec(i);
                                       constant:=true;
                                    end;
                               end;
                             if not constant then
                               begin
                                  write(outfile,'array[0..(');
                                  write_expr(outfile,p^.p2);
                                  write(outfile,')-1] of ');
                               end
                             else
                               begin
                                  write(outfile,'array[0..',i,'] of ');
                               end;
                             flush(outfile);
                             write_p_a_def(outfile,p^.p1,simple_type);
                          end;
            else internalerror(1);
         end;
      end;

    procedure write_type_specifier(var outfile:text; p : presobject);
      var
         hp1,hp2,hp3,lastexpr : presobject;
         i,l,w : longint;
         error : integer;
         mask : cardinal;
         flag_index,current_power : longint;
         current_level : byte;
         is_sized : boolean;

      begin
         case p^.typ of
            t_id :
              write(outfile,p^.p);
            { what can we do with void defs  ? }
            t_void :
              write(outfile,'void');
            t_pointerdef :
              begin
                 write(outfile,'p');
                 write_type_specifier(outfile,p^.p1);
              end;
            t_enumdef :
              begin
                 if (typedef_level>1) and (p^.p1=nil) and
                    (p^.p2^.typ=t_id) then
                   begin
                      write(outfile,p^.p2^.p);
                   end
                 else
                 if not EnumToConst then
                   begin
                      write(outfile,'(');
                      hp1:=p^.p1;
                      w:=length(aktspace);
                      while assigned(hp1) do
                        begin
                           write(outfile,hp1^.p1^.p);
                           if assigned(hp1^.p2) then
                             begin
                                write(outfile,' := ');
                                write_expr(outfile,hp1^.p2);
                                w:=w+6;(* strlen(hp1^.p); *)
                             end;
                           w:=w+length(hp1^.p1^.str);
                           hp1:=hp1^.next;
                           if assigned(hp1) then
                             write(outfile,',');
                           if w>40 then
                             begin
                                 writeln(outfile);
                                 write(outfile,aktspace);
                                 w:=length(aktspace);
                             end;
                           flush(outfile);
                        end;
                      write(outfile,')');
                      flush(outfile);
                   end
                 else
                   begin
                      Writeln (outfile,' Longint;');
                      hp1:=p^.p1;
                      l:=0;
                      lastexpr:=nil;
                      Writeln (outfile,aktspace,'Const');
                      while assigned(hp1) do
                        begin
                           write (outfile,aktspace,hp1^.p1^.p,' = ');
                           if assigned(hp1^.p2) then
                             begin
                                write_expr(outfile,hp1^.p2);
                                writeln(outfile,';');
                                lastexpr:=hp1^.p2;
                                if lastexpr^.typ=t_id then
                                  begin
                                     val(lastexpr^.str,l,error);
                                     if error=0 then
                                       begin
                                          inc(l);
                                          lastexpr:=nil;
                                       end
                                     else
                                       l:=1;
                                  end
                                else
                                  l:=1;
                             end
                           else
                             begin
                                if assigned(lastexpr) then
                                  begin
                                     write(outfile,'(');
                                     write_expr(outfile,lastexpr);
                                     writeln(outfile,')+',l,';');
                                  end
                                else
                                  writeln (outfile,l,';');
                                inc(l);
                             end;
                           hp1:=hp1^.next;
                           flush(outfile);
                        end;
                      block_type:=bt_const;
                  end;
               end;
            t_structdef :
              begin
                 inc(typedef_level);
                 flag_index:=-1;
                 is_sized:=false;
                 current_level:=0;
                 if (typedef_level>1) and (p^.p1=nil) and
                    (p^.p2^.typ=t_id) then
                   begin
                      write(outfile,p^.p2^.p);
                   end
                 else
                   begin
                      writeln(outfile,'record');
                      shift(3);
                      hp1:=p^.p1;

                      (* walk through all members *)
                      while assigned(hp1) do
                        begin
                           (* hp2 is t_memberdec *)
                           hp2:=hp1^.p1;
                           (*  hp3 is t_declist *)
                           hp3:=hp2^.p2;
                           while assigned(hp3) do
                             begin
                                if not assigned(hp3^.p1^.p3) or
                                   (hp3^.p1^.p3^.typ <> t_size_specifier) then
                                  begin
                                     if is_sized then
                                       begin
                                          if current_level <= 16 then
                                            writeln(outfile,'word;')
                                          else if current_level <= 32 then
                                            writeln(outfile,'longint;')
                                          else
                                            internalerror(11);
                                          is_sized:=false;
                                       end;

                                     write(outfile,aktspace,hp3^.p1^.p2^.p);
                                     write(outfile,' : ');
                                     shift(2);
                                     write_p_a_def(outfile,hp3^.p1^.p1,hp2^.p1);
                                     popshift;
                                  end;
                                { size specifier  or default value ? }
                                if assigned(hp3^.p1^.p3) then
                                  begin
                                     { we could use mask to implement this }
                                     { because we need to respect the positions }
                                     if hp3^.p1^.p3^.typ = t_size_specifier then
                                       begin
                                          if not is_sized then
                                            begin
                                               current_power:=1;
                                               current_level:=0;
                                               inc(flag_index);
                                               write(outfile,aktspace,'flag',flag_index,' : ');
                                            end;
                                          must_write_packed_field:=true;
                                          is_sized:=true;
                                          { can it be something else than a constant ? }
                                          { it can be a macro !! }
                                          if hp3^.p1^.p3^.p1^.typ=t_id then
                                            begin
                                              val(hp3^.p1^.p3^.p1^.str,l,error);
                                              if error=0 then
                                                begin
                                                   mask:=0;
                                                   for i:=1 to l do
                                                     begin
                                                        mask:=mask+current_power;
                                                        current_power:=current_power*2;
                                                     end;
                                                   write(tempfile,'bm_&',hp3^.p1^.p2^.p);
                                                   writeln(tempfile,' = ',hexstr(mask),';');
                                                   write(tempfile,'bp_&',hp3^.p1^.p2^.p);
                                                   writeln(tempfile,' = ',current_level,';');
                                                   current_level:=current_level + l;
                                                   { go to next flag if 31 }
                                                   if current_level = 32 then
                                                     begin
                                                        write(outfile,'longint');
                                                        is_sized:=false;
                                                     end;
                                                end;
                                            end;

                                       end
                                     else if hp3^.p1^.p3^.typ = t_default_value then
                                       begin
                                          write(outfile,'{=');
                                          write_expr(outfile,hp3^.p1^.p3^.p1);
                                          write(outfile,' ignored}');
                                       end;
                                  end;
                                if not is_sized then
                                  begin
                                     if is_procvar then
                                       begin
                                          if not no_pop then
                                            begin
                                               write(outfile,';cdecl');
                                               no_pop:=true;
                                            end;
                                          is_procvar:=false;
                                       end;
                                     writeln(outfile,';');
                                  end;
                                hp3:=hp3^.next;
                             end;
                           hp1:=hp1^.next;
                        end;
                      if is_sized then
                        begin
                           if current_level <= 16 then
                             writeln(outfile,'word;')
                           else if current_level <= 32 then
                             writeln(outfile,'longint;')
                           else
                             internalerror(11);
                           is_sized:=false;
                        end;
                      popshift;
                      write(outfile,aktspace,'end');
                      flush(outfile);
                   end;
                 dec(typedef_level);
              end;
            t_uniondef :
              begin
                 if (typedef_level>1) and (p^.p1=nil) and
                    (p^.p2^.typ=t_id) then
                   begin
                      write(outfile,p^.p2^.p);
                   end
                 else
                   begin
                      inc(typedef_level);
                      writeln(outfile,'record');
                      shift(2);
                      writeln(outfile,aktspace,'case longint of');
                      shift(3);
                      l:=0;
                      hp1:=p^.p1;

                      (* walk through all members *)
                      while assigned(hp1) do
                        begin
                           (* hp2 is t_memberdec *)
                           hp2:=hp1^.p1;
                           (* hp3 is t_declist *)
                           hp3:=hp2^.p2;
                           while assigned(hp3) do
                             begin
                                write(outfile,aktspace,l,' : ( ');
                                write(outfile,hp3^.p1^.p2^.p,' : ');
                                shift(2);
                                write_p_a_def(outfile,hp3^.p1^.p1,hp2^.p1);
                                popshift;
                                writeln(outfile,' );');
                                hp3:=hp3^.next;
                                inc(l);
                             end;
                           hp1:=hp1^.next;
                        end;
                      popshift;
                      write(outfile,aktspace,'end');
                      popshift;
                      flush(outfile);
                      dec(typedef_level);
                   end;
              end;
            else
              internalerror(3);
         end;
      end;

    procedure write_def_params(var outfile:text; p : presobject);
      var
         hp1 : presobject;
      begin
         case p^.typ of
            t_enumdef : begin
                           hp1:=p^.p1;
                           while assigned(hp1) do
                             begin
                                write(outfile,hp1^.p1^.p);
                                hp1:=hp1^.next;
                                if assigned(hp1) then
                                  write(outfile,',')
                                else
                                  write(outfile);
                                flush(outfile);
                             end;
                           flush(outfile);
                        end;
         else internalerror(4);
         end;
      end;

%}

%token TYPEDEF DEFINE
%token COLON SEMICOLON COMMA
%token LKLAMMER RKLAMMER LECKKLAMMER RECKKLAMMER
%token LGKLAMMER RGKLAMMER
%token STRUCT UNION ENUM
%token ID NUMBER CSTRING
%token SHORT UNSIGNED LONG INT REAL _CHAR
%token VOID _CONST
%token _FAR _HUGE _NEAR
%token _ASSIGN NEW_LINE SPACE_DEFINE
%token EXTERN STDCALL CDECL CALLBACK PASCAL WINAPI APIENTRY WINGDIAPI SYS_TRAP
%token _PACKED
%token ELLIPSIS
%right R_AND
%left EQUAL UNEQUAL GT LT GTE LTE
%left QUESTIONMARK COLON
%left _OR
%left _AND
%left _PLUS MINUS
%left _SHR _SHL
%left STAR _SLASH
%right _NOT
%right LKLAMMER
%right PSTAR
%right P_AND
%right LECKKLAMMER
%left POINT DEREF
%left COMMA
%left STICK
%%

file : declaration_list
     ;

error_info : { writeln(outfile,'(* error ');
               writeln(outfile,prev_line);
               writeln(outfile,last_source_line);
             };

declaration_list : declaration_list  declaration
     {  if yydebug then writeln('declaration reduced at line ',line_no);
        if yydebug then writeln(outfile,'(* declaration reduced *)');
     }
     | declaration_list define_dec
     {  if yydebug then writeln('define declaration reduced at line ',line_no);
        if yydebug then writeln(outfile,'(* define declaration reduced *)');
     }
     | declaration
     {  if yydebug then writeln('declaration reduced at line ',line_no);
     }
     | define_dec
     {  if yydebug then writeln('define declaration reduced at line ',line_no);
     }
     ;

dec_specifier :
     EXTERN { $$:=new(presobject,init_id('extern')); }
     |{ $$:=new(presobject,init_id('intern')); }
     ;

dec_modifier :
     STDCALL { $$:=new(presobject,init_id('no_pop')); }
     | CDECL { $$:=new(presobject,init_id('cdecl')); }
     | CALLBACK { $$:=new(presobject,init_id('no_pop')); }
     | PASCAL { $$:=new(presobject,init_id('no_pop')); }
     | WINAPI { $$:=new(presobject,init_id('no_pop')); }
     | APIENTRY { $$:=new(presobject,init_id('no_pop')); }
     | WINGDIAPI { $$:=new(presobject,init_id('no_pop')); }
     | { $$:=nil }
     ;

systrap_specifier:
     SYS_TRAP LKLAMMER dname RKLAMMER { $$:=$3; }
     | { $$:=nil; }
     ;

declaration :
     dec_specifier type_specifier dec_modifier declarator_list systrap_specifier SEMICOLON
     { IsExtern:=false;
       (* by default we must pop the args pushed on stack *)
       no_pop:=false;
    (* writeln(outfile,'{ dec_specifier type_specifier declarator_list SEMICOLON}');

     if assigned($3) then writeln(outfile,'{*$3}');
     if assigned($3)and assigned($3.p1)
         then writeln(outfile,'{*$3^.p1}');
     if assigned($3)and assigned($3^.p1)and assigned($3^.p1^.p1)
         then writeln(outfile,'{*$3^.p1^.p1}');
    *)

      if (assigned($4)and assigned($4^.p1)and assigned($4^.p1^.p1))
        and ($4^.p1^.p1^.typ=t_procdef) then
         begin
            If UseLib then
              IsExtern:=true
            else
              IsExtern:=assigned($1)and($1^.str='extern');
            no_pop:=assigned($3) and ($3^.str='no_pop');
            if block_type<>bt_func then
              writeln(outfile);

            block_type:=bt_func;
            write(outfile,aktspace);
            write(extfile,aktspace);
            (* distinguish between procedure and function *)
            if assigned($2) then
            if ($2^.typ=t_void) and ($4^.p1^.p1^.p1=nil) then
              begin
               write(outfile,'procedure ',$4^.p1^.p2^.p);
                 (* write arguments *)
               shift(10);
               if assigned($4^.p1^.p1^.p2) then
                   write_args(outfile,$4^.p1^.p1^.p2);
               write(extfile,'procedure ',$4^.p1^.p2^.p);
               (* write arguments *)
               if assigned($4^.p1^.p1^.p2) then
                 write_args(extfile,$4^.p1^.p1^.p2);
              end
            else
              begin
                 write(outfile,'function ',$4^.p1^.p2^.p);
                 write(extfile,'function ',$4^.p1^.p2^.p);

                 shift(9);
                 (* write arguments *)
                 if assigned($4^.p1^.p1^.p2) then
                   write_args(outfile,$4^.p1^.p1^.p2);
                 if assigned($4^.p1^.p1^.p2) then
                   write_args(extfile,$4^.p1^.p1^.p2);

                 write(outfile,':');
                 write(extfile,':');
                 write_p_a_def(outfile,$4^.p1^.p1^.p1,$2);
                 write_p_a_def(extfile,$4^.p1^.p1^.p1,$2);
              end;

            if assigned($5) then
              write(outfile,';systrap ',$5^.p);

            (* No CDECL in interface for Uselib *)
            if IsExtern and (not no_pop) then
             begin
               write(outfile,';cdecl');
               write(extfile,';cdecl');
             end;
            popshift;
            if UseLib then
              begin
                if IsExtern then
                  begin
                    write (extfile,';external');
                    If UseName then
                     Write(extfile,' External_library name ''',$4^.p1^.p2^.p,'''');
                  end;
                writeln(extfile,';');
                writeln(outfile,';');
              end
            else
              begin
                writeln(extfile,';');
                writeln(outfile,';');
                if not IsExtern then
                 begin
                   writeln(extfile,aktspace,'  begin');
                   writeln(extfile,aktspace,'     { You must implemented this function }');
                   writeln(extfile,aktspace,'  end;');
                 end;
              end;
            IsExtern:=false;
            writeln(outfile);
            if Uselib then
              writeln(extfile);
         end
       else (* $4^.p1^.p1^.typ=t_procdef *)
       if assigned($4)and assigned($4^.p1) then
         begin
            shift(2);
            if block_type<>bt_var then
              begin
                 writeln(outfile);
                 writeln(outfile,aktspace,'var');
              end;
            block_type:=bt_var;

            shift(3);

            IsExtern:=assigned($1)and($1^.str='extern');
            (* walk through all declarations *)
            hp:=$4;
            while assigned(hp) and assigned(hp^.p1) do
              begin
                 (* write new var name *)
                 if assigned(hp^.p1^.p2)and assigned(hp^.p1^.p2^.p)then
                   write(outfile,aktspace,hp^.p1^.p2^.p);
                 write(outfile,' : ');
                 shift(2);
                 (* write its type *)
                 write_p_a_def(outfile,hp^.p1^.p1,$2);
                 if assigned(hp^.p1^.p2)and assigned(hp^.p1^.p2^.p)then
                   begin
                      if isExtern then
                        write(outfile,';cvar;external')
                      else
                        write(outfile,';cvar;export');
                      write(outfile,hp^.p1^.p2^.p);
                   end;
                 writeln(outfile,''';');
                 popshift;
                 hp:=hp^.p2;
              end;
            popshift;
            popshift;
         end;
       if assigned($1)then  dispose($1,done);
       if assigned($2)then  dispose($2,done);
       if assigned($4)then  dispose($4,done);
     } |
     special_type_specifier SEMICOLON
     {
       if block_type<>bt_type then
         begin
            writeln(outfile);
            writeln(outfile,aktspace,'type');
         end;
       block_type:=bt_type;
       shift(3);
       (* write new type name *)
       TN:=strpas($1^.p2^.p);
       if ($1^.typ=t_structdef) or ($1^.typ=t_uniondef) then
         begin
            PN:='P'+strpas($1^.p2^.p);
            if PrependTypes then
              TN:='T'+TN;
            if UsePPointers then
              Writeln (outfile,aktspace,PN,' = ^',TN,';');
         end;
       write(outfile,aktspace,TN,' = ');
       shift(2);
       hp:=$1;
       write_type_specifier(outfile,hp);
       popshift;
       (* enum_to_const can make a switch to const *)
       if block_type=bt_type then writeln(outfile,';');
       writeln(outfile);
       flush(outfile);
       popshift;
       if must_write_packed_field then
         write_packed_fields_info(outfile,hp,TN);
       if assigned(hp) then
         dispose(hp,done);
     } |
     TYPEDEF type_specifier dec_modifier declarator_list SEMICOLON
     {
       if block_type<>bt_type then
         begin
            writeln(outfile);
            writeln(outfile,aktspace,'type');
         end;
       block_type:=bt_type;

       no_pop:=assigned($3) and ($3^.str='no_pop');
       shift(3);
       (* walk through all declarations *)
       hp:=$4;
       ph:=nil;
       is_procvar:=false;
       while assigned(hp) do
         begin
            writeln(outfile);
            (* write new type name *)
            write(outfile,aktspace,hp^.p1^.p2^.p);
            write(outfile,' = ');
            shift(2);
            if assigned(ph) then
              write_p_a_def(outfile,hp^.p1^.p1,ph)
            else
              write_p_a_def(outfile,hp^.p1^.p1,$2);
            (* simple def ?
               keep the name for the other defs *)
            if (ph=nil) and (hp^.p1^.p1=nil) then
              ph:=hp^.p1^.p2;
            popshift;
            (* if no_pop it is normal fpc calling convention *)
            if is_procvar and
               (not no_pop) then
              write(outfile,';cdecl');
            writeln(outfile,';');
            flush(outfile);
            hp:=hp^.next;
         end;
       (* write tag name *)
       if assigned(ph) and
         (($2^.typ=t_structdef) or
         ($2^.typ=t_enumdef) or
         ($2^.typ=t_uniondef)) and
         assigned($2^.p2) then
           begin
              writeln(outfile);
              write(outfile,aktspace,$2^.p2^.p,' = ');
              if assigned(ph) then
                writeln(outfile,ph^.p,';')
              else
                begin
                   write_p_a_def(outfile,hp^.p1^.p1,$2);
                   writeln(outfile,';');
                end;
           end;
       popshift;
       if must_write_packed_field then
         if assigned(ph) then
           write_packed_fields_info(outfile,$2,ph^.str)
         else if assigned($2^.p2) then
           write_packed_fields_info(outfile,$2,$2^.p2^.str);
       if assigned($2)then
       dispose($2,done);
       if assigned($3)then
       dispose($3,done);
       if assigned($4)then
       dispose($4,done);
     } |
     TYPEDEF dname SEMICOLON
     {
       if block_type<>bt_type then
         begin
            writeln(outfile);
            writeln(outfile,aktspace,'type');
         end;
       block_type:=bt_type;

       shift(3);
       (* write as pointer *)
       writeln(outfile);
       writeln(outfile,'(* generic typedef  *)');
       writeln(outfile,aktspace,$2^.p,' = pointer;');
       flush(outfile);
       popshift;
       if assigned($2)then
       dispose($2,done);
     }
     | error  error_info SEMICOLON
      { writeln(outfile,'in declaration at line ',line_no,' *)');
        aktspace:='';
        in_space_define:=0;
        in_define:=false;
        arglevel:=0;
        if_nb:=0;
        aktspace:='    ';
        space_index:=1;
        yyerrok;}
     ;

define_dec :
     DEFINE dname LKLAMMER enum_list RKLAMMER SPACE_DEFINE def_expr NEW_LINE
     {
       writeln (outfile,aktspace,'{ was #define dname(params) def_expr }');
       writeln (extfile,aktspace,'{ was #define dname(params) def_expr }');
       if assigned($4) then
         begin
            writeln (outfile,aktspace,'{ argument types are unknown }');
            writeln (extfile,aktspace,'{ argument types are unknown }');
         end;
       if not assigned($7^.p3) then
         begin
            writeln(outfile,aktspace,'{ return type might be wrong }   ');
            writeln(extfile,aktspace,'{ return type might be wrong }   ');
         end;
       block_type:=bt_func;
       write(outfile,aktspace,'function ',$2^.p);
       write(extfile,aktspace,'function ',$2^.p);

       if assigned($4) then
         begin
            write(outfile,'(');
            write(extfile,'(');
            ph:=new(presobject,init_one(t_enumdef,$4));
            write_def_params(outfile,ph);
            write_def_params(extfile,ph);
            if assigned(ph) then dispose(ph,done);
            ph:=nil;
            (* types are unknown *)
            write(outfile,' : longint)');
            write(extfile,' : longint)');
         end;
       if not assigned($7^.p3) then
         begin
            writeln(outfile,' : longint;');
            writeln(outfile,aktspace,'  { return type might be wrong }   ');
            flush(outfile);
            writeln(extfile,' : longint;');
            writeln(extfile,aktspace,'  { return type might be wrong }   ');
         end
       else
         begin
            write(outfile,' : ');
            write_type_specifier(outfile,$7^.p3);
            writeln(outfile,';');
            flush(outfile);
            write(extfile,' : ');
            write_type_specifier(extfile,$7^.p3);
            writeln(extfile,';');
         end;
       writeln(outfile);
       flush(outfile);
       hp:=new(presobject,init_two(t_funcname,$2,$7));
       write_funexpr(extfile,hp);
       writeln(extfile);
       flush(extfile);
       if assigned(hp)then dispose(hp,done);
     }|
     DEFINE dname SPACE_DEFINE NEW_LINE
     {
       writeln(outfile,'{$define ',$2^.p,'}');
       flush(outfile);
       if assigned($2)then
        dispose($2,done);
     }|
     DEFINE dname NEW_LINE
     {
       writeln(outfile,'{$define ',$2^.p,'}');
       flush(outfile);
       if assigned($2)then
        dispose($2,done);
     } |
     DEFINE dname SPACE_DEFINE def_expr NEW_LINE
     {
       if ($4^.typ=t_exprlist) and
          $4^.p1^.is_const and
          not assigned($4^.next) then
         begin
            if block_type<>bt_const then
              begin
                 writeln(outfile);
                 writeln(outfile,aktspace,'const');
              end;
            block_type:=bt_const;

            aktspace:=aktspace+'   ';
            write(outfile,aktspace,$2^.p);
            write(outfile,' = ');
            flush(outfile);
            write_expr(outfile,$4^.p1);
            writeln(outfile,';');
            dec(byte(aktspace[0]),3);
            if assigned($2) then
            dispose($2,done);
            if assigned($4) then
            dispose($4,done);
         end
       else
         begin
            aktspace:=aktspace+'  ';
            writeln (outfile,aktspace,'{ was #define dname def_expr }');
            writeln (extfile,aktspace,'{ was #define dname def_expr }');
            block_type:=bt_func;
            write(outfile,aktspace,'function ',$2^.p);
            write(extfile,aktspace,'function ',$2^.p);
            if not assigned($4^.p3) then
              begin
                 writeln(outfile,' : longint;');
                 writeln(outfile,aktspace,'  { return type might be wrong }');
                 flush(outfile);
                 writeln(extfile,' : longint;');
                 writeln(extfile,aktspace,'  { return type might be wrong }');
              end
            else
              begin
                 write(outfile,' : ');
                 write_type_specifier(outfile,$4^.p3);
                 writeln(outfile,';');
                 flush(outfile);
                 write(extfile,' : ');
                 write_type_specifier(extfile,$4^.p3);
                 writeln(extfile,';');
              end;
            writeln(outfile);
            flush(outfile);
            hp:=new(presobject,init_two(t_funcname,$2,$4));
            write_funexpr(extfile,hp);
            dec(byte(aktspace[0]),2);
            dispose(hp,done);
            writeln(extfile);
            flush(extfile);
         end;
     }
     | error error_info NEW_LINE
      { writeln(outfile,'in define line ',line_no,' *)');
        aktspace:='';
        in_space_define:=0;
        in_define:=false;
        arglevel:=0;
        if_nb:=0;
        aktspace:='    ';
        space_index:=1;

        yyerrok;}
     ;

closed_list : LGKLAMMER member_list RGKLAMMER
            {$$:=$2;} |
            error  error_info RGKLAMMER
            { writeln(outfile,' in member_list *)');
            yyerrok;
            $$:=nil;
            }
            ;

closed_enum_list : LGKLAMMER enum_list RGKLAMMER
            {$$:=$2;} |
            error  error_info  RGKLAMMER
            { writeln(outfile,' in enum_list *)');
            yyerrok;
            $$:=nil;
            }
            ;

special_type_specifier :
     STRUCT dname closed_list _PACKED
     {
       if not is_packed then
         writeln(outfile,'{$PACKRECORDS 1}');
       is_packed:=true;
       $$:=new(presobject,init_two(t_structdef,$3,$2));
     } |
     STRUCT dname closed_list
     {
       if is_packed then
         writeln(outfile,'{$PACKRECORDS 4}');
       is_packed:=false;
       $$:=new(presobject,init_two(t_structdef,$3,$2));
     } |
     UNION dname closed_list _PACKED
     {
       if not is_packed then
         writeln(outfile,'{$PACKRECORDS 1}');
       is_packed:=true;
       $$:=new(presobject,init_two(t_uniondef,$3,$2));
     } |
     UNION dname closed_list
     {
       $$:=new(presobject,init_two(t_uniondef,$3,$2));
     } |
     UNION dname
     {
       $$:=new(presobject,init_two(t_uniondef,nil,$2));
     } |
     STRUCT dname
     {
       $$:=new(presobject,init_two(t_structdef,nil,$2));
     } |
     ENUM dname closed_enum_list
     {
       $$:=new(presobject,init_two(t_enumdef,$3,$2));
     } |
     ENUM dname
     {
       $$:=new(presobject,init_two(t_enumdef,nil,$2));
     };

type_specifier :
      _CONST type_specifier
      {
        writeln(outfile,'(* Const before type ignored *)');
        $$:=$2;
        } |
     UNION closed_list  _PACKED
     {
       if not is_packed then
         writeln(outfile,'{$PACKRECORDS 1}');
       is_packed:=true;
       $$:=new(presobject,init_one(t_uniondef,$2));
     } |
     UNION closed_list
     {
       $$:=new(presobject,init_one(t_uniondef,$2));
     } |
     STRUCT closed_list _PACKED
     {
       if not is_packed then
         writeln(outfile,'{$PACKRECORDS 1}');
       is_packed:=true;
       $$:=new(presobject,init_one(t_structdef,$2));
     } |
     STRUCT closed_list
     {
       if is_packed then
         writeln(outfile,'{$PACKRECORDS 4}');
       is_packed:=false;
       $$:=new(presobject,init_one(t_structdef,$2));
     } |
     ENUM closed_enum_list
     {
       $$:=new(presobject,init_one(t_enumdef,$2));
     } |
     special_type_specifier
     {
       $$:=$1;
     } |
     simple_type_name { $$:=$1; }
     ;

member_list : member_declaration member_list
     {
       $$:=new(presobject,init_one(t_memberdeclist,$1));
       $$^.next:=$2;
     } |
     member_declaration
     {
       $$:=new(presobject,init_one(t_memberdeclist,$1));
     }
     ;

member_declaration :
     type_specifier declarator_list SEMICOLON
     {
       $$:=new(presobject,init_two(t_memberdec,$1,$2));
     }
     ;

dname : ID { (*dname*)
           $$:=new(presobject,init_id(act_token));
           }
     ;

special_type_name : INT
     {
       $$:=new(presobject,init_id(INT_STR));
     } |
     UNSIGNED INT
     {
       $$:=new(presobject,init_id(UINT_STR));
     } |
     LONG
     {
       $$:=new(presobject,init_id(INT_STR));
     } |
     REAL
     {
       $$:=new(presobject,init_id(REAL_STR));
     } |
     LONG INT
     {
       $$:=new(presobject,init_id(INT_STR));
     } |
     UNSIGNED LONG INT
     {
       $$:=new(presobject,init_id(UINT_STR));
     } |
     UNSIGNED LONG
     {
       $$:=new(presobject,init_id(UINT_STR));
     } |
     UNSIGNED
     {
       $$:=new(presobject,init_id(UINT_STR));
     } |
     UNSIGNED SHORT
     {
       $$:=new(presobject,init_id(USHORT_STR));
     } |
     UNSIGNED _CHAR
     {
       $$:=new(presobject,init_id(UCHAR_STR));
     } |
     VOID
     {
       $$:=new(presobject,init_no(t_void));
     } |
     SHORT
     {
       $$:=new(presobject,init_id(SHORT_STR));
     } |
     _CHAR
     {
       $$:=new(presobject,init_id(CHAR_STR));
     }
     ;

simple_type_name :
     special_type_name
     {
     $$:=$1;
     }
     |
     dname
     {
     $$:=$1;
     }
     ;

declarator_list :
     declarator_list COMMA declarator
     {
     $$:=$1;
     hp:=$1;
     while assigned(hp^.next) do
       hp:=hp^.next;
     hp^.next:=new(presobject,init_one(t_declist,$3));
     }|
     error error_info COMMA declarator_list
     {
     writeln(outfile,' in declarator_list *)');
     $$:=$4;
     yyerrok;
     }|
     error error_info
     {
     writeln(outfile,' in declarator_list *)');
     yyerrok;
     }|
     declarator
     {
     $$:=new(presobject,init_one(t_declist,$1));
     }
     ;

argument_declaration : type_specifier declarator
     {
       $$:=new(presobject,init_two(t_arg,$1,$2));
     } |
     type_specifier abstract_declarator
     {
       $$:=new(presobject,init_two(t_arg,$1,$2));
     }
     ;

argument_declaration_list : argument_declaration
     {
       $$:=new(presobject,init_two(t_arglist,$1,nil));
     } |
     argument_declaration COMMA argument_declaration_list
     {
       $$:=new(presobject,init_two(t_arglist,$1,nil));
       $$^.next:=$3;
     } |
     ELLIPSIS
     {
       $$:=new(presobject,init_two(t_arglist,ellipsisarg,nil));
       (*** ELLIPSIS PROBLEM ***)
     }
     ;

size_overrider :
       _FAR
       { $$:=new(presobject,init_id('far'));}
       | _NEAR
       { $$:=new(presobject,init_id('near'));}
       | _HUGE
       { $$:=new(presobject,init_id('huge'));}
       ;

declarator :
      _CONST declarator
      {
        writeln(outfile,'(* Const before declarator ignored *)');
        $$:=$2;
        } |
     size_overrider STAR declarator
     {
       writeln(outfile,aktspace,'(* ',$1^.p,' ignored *)');
       dispose($1,done);
       hp:=$3;
       $$:=hp;
       while assigned(hp^.p1) do
         hp:=hp^.p1;
       hp^.p1:=new(presobject,init_one(t_pointerdef,nil));
     } |
     STAR declarator
     {
       (* %prec PSTAR     this was wrong!! *)
       hp:=$2;
       $$:=hp;
       while assigned(hp^.p1) do
         hp:=hp^.p1;
       hp^.p1:=new(presobject,init_one(t_pointerdef,nil));
     } |
     _AND declarator %prec P_AND
     {
       hp:=$2;
       $$:=hp;
       while assigned(hp^.p1) do
         hp:=hp^.p1;
       hp^.p1:=new(presobject,init_one(t_addrdef,nil));
     } |
     dname COLON expr
       {
         (*  size specifier supported *)
         hp:=new(presobject,init_one(t_size_specifier,$3));
         $$:=new(presobject,init_three(t_dec,nil,$1,hp));
        }|
     dname ASSIGN expr
       {
         writeln(outfile,'(* Warning : default value for ',$1^.p,' ignored *)');
         hp:=new(presobject,init_one(t_default_value,$3));
         $$:=new(presobject,init_three(t_dec,nil,$1,hp));
        }|
     dname
       {
         $$:=new(presobject,init_two(t_dec,nil,$1));
        }|
     declarator LKLAMMER argument_declaration_list RKLAMMER
     {
       hp:=$1;
       $$:=hp;
       while assigned(hp^.p1) do
         hp:=hp^.p1;
       hp^.p1:=new(presobject,init_two(t_procdef,nil,$3));
     } |
     declarator no_arg
     {
       hp:=$1;
       $$:=hp;
       while assigned(hp^.p1) do
         hp:=hp^.p1;
       hp^.p1:=new(presobject,init_two(t_procdef,nil,nil));
     } |
     declarator LECKKLAMMER expr RECKKLAMMER
     {
       hp:=$1;
       $$:=hp;
       while assigned(hp^.p1) do
         hp:=hp^.p1;
       hp^.p1:=new(presobject,init_two(t_arraydef,nil,$3));
     } |
     LKLAMMER declarator RKLAMMER { $$:=$2; }
     ;

no_arg : LKLAMMER RKLAMMER |
        LKLAMMER VOID RKLAMMER;

abstract_declarator :
      _CONST abstract_declarator
      {
        writeln(outfile,'(* Const before abstract_declarator ignored *)');
        $$:=$2;
        } |
     size_overrider STAR abstract_declarator
     {
       writeln(outfile,aktspace,'(* ',$1^.p,' ignored *)');
       dispose($1,done);
       hp:=$3;
       $$:=hp;
       while assigned(hp^.p1) do
         hp:=hp^.p1;
       hp^.p1:=new(presobject,init_one(t_pointerdef,nil));
     } |
     STAR abstract_declarator %prec PSTAR
     {
       hp:=$2;
       $$:=hp;
       while assigned(hp^.p1) do
         hp:=hp^.p1;
       hp^.p1:=new(presobject,init_one(t_pointerdef,nil));
     } |
     abstract_declarator LKLAMMER argument_declaration_list RKLAMMER
     {
       hp:=$1;
       $$:=hp;
       while assigned(hp^.p1) do
         hp:=hp^.p1;
       hp^.p1:=new(presobject,init_two(t_procdef,nil,$3));
     } |
     abstract_declarator no_arg
     {
       hp:=$1;
       $$:=hp;
       while assigned(hp^.p1) do
         hp:=hp^.p1;
       hp^.p1:=new(presobject,init_two(t_procdef,nil,nil));
     } |
     abstract_declarator LECKKLAMMER expr RECKKLAMMER
     {
       hp:=$1;
       $$:=hp;
       while assigned(hp^.p1) do
         hp:=hp^.p1;
       hp^.p1:=new(presobject,init_two(t_arraydef,nil,$3));
     } |
     LKLAMMER abstract_declarator RKLAMMER
     { $$:=$2; } |
     {
       $$:=new(presobject,init_two(t_dec,nil,nil));
     }
     ;

expr    :
          shift_expr
          {$$:=$1;}
          ;

shift_expr :
          expr EQUAL expr
          { $$:=new(presobject,init_bop(' = ',$1,$3));}
          | expr UNEQUAL expr
          { $$:=new(presobject,init_bop(' <> ',$1,$3));}
          | expr GT expr
          { $$:=new(presobject,init_bop(' > ',$1,$3));}
          | expr GTE expr
          { $$:=new(presobject,init_bop(' >= ',$1,$3));}
          | expr LT expr
          { $$:=new(presobject,init_bop(' < ',$1,$3));}
          | expr LTE expr
          { $$:=new(presobject,init_bop(' <= ',$1,$3));}
          | expr _PLUS expr
          { $$:=new(presobject,init_bop(' + ',$1,$3));}
               | expr MINUS expr
          { $$:=new(presobject,init_bop(' - ',$1,$3));}
               | expr STAR expr
          { $$:=new(presobject,init_bop(' * ',$1,$3));}
               | expr _SLASH expr
          { $$:=new(presobject,init_bop(' / ',$1,$3));}
               | expr _OR expr
          { $$:=new(presobject,init_bop(' or ',$1,$3));}
               | expr _AND expr
          { $$:=new(presobject,init_bop(' and ',$1,$3));}
               | expr _NOT expr
          { $$:=new(presobject,init_bop(' not ',$1,$3));}
               | expr _SHL expr
          { $$:=new(presobject,init_bop(' shl ',$1,$3));}
               | expr _SHR expr
          { $$:=new(presobject,init_bop(' shr ',$1,$3));}
          | expr QUESTIONMARK colon_expr
          { $3^.p1:=$1;
          $$:=$3;
          inc(if_nb);
          $$^.p:=strpnew('if_local'+str(if_nb));
          } |
          unary_expr {$$:=$1;}
          ;

colon_expr : expr COLON expr
       { (* if A then B else C *)
       $$:=new(presobject,init_three(t_ifexpr,nil,$1,$3));}
       ;

maybe_empty_unary_expr :
                  unary_expr
                  { $$:=$1; }
                  |
                  { $$:=nil;}
                  ;

unary_expr:
     dname
     {
     $$:=$1;
     } |
     CSTRING
     {
     (* remove L prefix for widestrings *)
     s:=act_token;
     if Win32headers and (s[1]='L') then
       delete(s,1,1);
     $$:=new(presobject,init_id(''''+copy(s,2,length(s)-2)+''''));
     } |
     NUMBER
     {
     $$:=new(presobject,init_id(act_token));
     } |
     unary_expr POINT expr
     {
     $$:=new(presobject,init_bop('.',$1,$3));
     } |
     unary_expr DEREF expr
     {
     $$:=new(presobject,init_bop('^.',$1,$3));
     } |
     MINUS unary_expr
     {
     $$:=new(presobject,init_preop('-',$2));
     }|
     _AND unary_expr %prec R_AND
     {
     $$:=new(presobject,init_preop('@',$2));
     }|
     _NOT unary_expr
     {
     $$:=new(presobject,init_preop(' not ',$2));
     } |
     LKLAMMER dname RKLAMMER maybe_empty_unary_expr
     {
     if assigned($4) then
       $$:=new(presobject,init_two(t_typespec,$2,$4))
     else
       $$:=$2;
     } |
     LKLAMMER type_specifier RKLAMMER unary_expr
     {
     $$:=new(presobject,init_two(t_typespec,$2,$4));
     } |
     LKLAMMER type_specifier STAR RKLAMMER unary_expr
     {
     hp:=new(presobject,init_one(t_pointerdef,$2));
     $$:=new(presobject,init_two(t_typespec,hp,$5));
     } |
     LKLAMMER type_specifier size_overrider STAR RKLAMMER unary_expr
     {
     writeln(outfile,aktspace,'(* ',$3^.p,' ignored *)');
     dispose($3,done);
     write_type_specifier(outfile,$2);
     writeln(outfile,' ignored *)');
     hp:=new(presobject,init_one(t_pointerdef,$2));
     $$:=new(presobject,init_two(t_typespec,hp,$6));
     } |
     dname LKLAMMER exprlist RKLAMMER
     {
     hp:=new(presobject,init_one(t_exprlist,$1));
     $$:=new(presobject,init_three(t_funexprlist,hp,$3,nil));
     } |
     LKLAMMER shift_expr RKLAMMER
     {
     $$:=$2;
     }
     ;

enum_list :
     enum_element COMMA enum_list
     { (*enum_element COMMA enum_list *)
       $$:=$1;
       $$^.next:=$3;
      } |
      enum_element {
       $$:=$1;
      } |
      {(* empty enum list *)
       $$:=nil;};

enum_element :
     dname _ASSIGN expr
     { begin (*enum_element: dname _ASSIGN expr *)
        $$:=new(presobject,init_two(t_enumlist,$1,$3));
       end;
     } |
     dname
     {
       begin (*enum_element: dname*)
       $$:=new(presobject,init_two(t_enumlist,$1,nil));
       end;
     };


def_expr : unary_expr
         {
         if $1^.typ=t_funexprlist then
           $$:=$1
         else
           $$:=new(presobject,init_two(t_exprlist,$1,nil));
         (* if here is a type specifier
            we know the return type *)
         if ($1^.typ=t_typespec) then
           $$^.p3:=$1^.p1^.get_copy;
         }
         ;

exprlist : exprelem COMMA exprlist
    { (*exprlist COMMA expr*)
       $$:=$1;
       $1^.next:=$3;
     } |
     exprelem
     {
       $$:=$1;
     } |
     { (* empty expression list *)
       $$:=nil; };

exprelem :
           expr
           {
             $$:=new(presobject,init_one(t_exprlist,$1));
           };

%%

function yylex : Integer;
 begin
 yylex:=scan.yylex;
 end;

var r:integer; SS:string;

begin
   debug:=true;
   yydebug:=true;
   aktspace:='  ';
   block_type:=bt_no;
   IsExtern:=false;
   Assign(extfile,'ext.tmp'); rewrite(extfile);
   Assign(tempfile,'ext2.tmp'); rewrite(tempfile);
   r:=yyparse;
   if not(includefile) then
     begin
        writeln(outfile);
        writeln(outfile,'  implementation');
        writeln(outfile);
        writeln(outfile,'const External_library=''',libfilename,'''; {Setup as you need!}');
        writeln(outfile);
     end;
   reset(extfile);

   { here we have a problem if a line is longer than 255 chars !! }
   while not eof(extfile) do
    begin
    readln(extfile,SS);
    writeln(outfile,SS);
    end;

   writeln(outfile);

   if not(includefile) then
     writeln(outfile,'end.');

   close(extfile);
   erase(extfile);
   close(outfile);
   close(tempfile);
   erase(tempfile);
   close(textinfile);
end.

(*

 $Log$
 Revision 1.1  1999/11/12 22:05:44  sven.bursch
 h2pas hinzugefuegt
 diverse Bugfixes

 Revision 1.1  1999/05/12 16:11:39  peter
   * moved

 Revision 1.22  1998/11/12 11:38:21  peter
   + new cdecl support
   + ... -> array of const

 Revision 1.21  1998/09/10 13:52:42  peter
   * removed warnings

 Revision 1.20  1998/09/04 17:26:32  pierre
   * better packed field handling

 Revision 1.18  1998/08/05 15:50:09  florian
   * small problems with // comments fixed (invalid line counting)
   + SYS_TRAP support for PalmOS
   + switch -x for PalmOS
   + switch -i to generate include files instead of units

 Revision 1.17  1998/07/27 11:03:48  florian
   * probelm with funtions which resturns a pointer solved

 Revision 1.16  1998/07/24 20:55:43  michael
 * Fixed some minor bugs in Pierres stuff

 Revision 1.15  1998/07/23 23:26:03  michael
 + added -D option instead of -d, restored old -d

 Revision 1.14  1998/06/12 16:53:52  pierre
   + syntax of C var changed again !!
     this reflect now the current state of the compiler
   * improvements in & address operator handling

 Revision 1.12  1998/06/08 08:13:44  pierre
   + merged version of h2pas
   + added -w for special win32 header directives

   5.1998 : reworked by Pierre Muller

     - added better parsing of defines
     - handles type casting
     - error recovery partially implemented
     - WIN32 specific stuff

     still missing
     - tags not stored
     - conditionnals inside typed definitions
     - complicated defines not supported
     ( sets .. use of ## ... )
     - what should we do about
      const specifier ? can we ignored this
      FAR modifier ?

 Revision 1.11  1998/04/30 11:22:20  florian
   + support of direct struct declaration added

 Revision 1.10  1998/04/27 12:06:40  michael
 + Added GPL statement

 Revision 1.9  1998/04/24 22:34:40  florian
   + enumerations with assigments implemented

 Revision 1.8  1998/04/24 18:23:46  florian
   + parameter -v added (replaces pointer parameters by call by reference
     parameters)
     void p(int *i) =>   procedure p(var i : longint);

 History:
   25.9.1996:
      first version

   26.9.1996:
      - structs are supported
      - unsigned implemented
      - procedure variables implemented
      - void * becomes pointer
      - unions implemented
      - enumerations
      - number post- and prefixes
      - operatores unary-, << and >>
      - problem with the priority of [], (), and * fixed
      - procedures and functions

   28.9.1996:
      - formal paramters

   22-26.5.1997  made by Mark Malakanov     mark@av.krasnoyarsk.su
      - full ariphmetic and logic expressions in #define

      - #define with params changes to function (first param
        disappears by unknown reason!).
        Adds func body into implementation section.

      - real numbers

      - handling
       #ifdef ID  to {$ifdef ID}
       #ifundef ID  to {$ifundef ID}
       #else to {$else}
       #define ID to {$define ID}
       #endif to {$endif}

      -"extern" fully handled . Adds proc/func + 'external _ExternalLibrary;'to
        implementation section
       you must assign _ExternalLibrary later.

      -"const" skips in func/proc arguments.

      changes in convert.y and scan.l
      - "convert" renamed to "h2pas"
      - Inserted the checking "IsAssigned(Pointer)" everywhere access to pointers
       It preserv from Acces Violation Errors.
      - A little remade for TP Lex and Yacc 4.01 -
           changed function "input" to "get_char"
      -!!! because of peculiarity TPLY4.01 you must create unit CONVERU.PAS by
       your hand! Cut const definitions from CONVERT.PAS and paste into CONVERU.PAS

 What need
   * handle struct a {  }; in the right way
   * all predefined C types
   * misplaced comments
   * handle functions without result
*)

