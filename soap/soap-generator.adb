------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                          Copyright (C) 2003-2004                         --
--                                ACT-Europe                                --
--                                                                          --
--  Authors: Dmitriy Anisimkov - Pascal Obry                                --
--                                                                          --
--  This library is free software; you can redistribute it and/or modify    --
--  it under the terms of the GNU General Public License as published by    --
--  the Free Software Foundation; either version 2 of the License, or (at   --
--  your option) any later version.                                         --
--                                                                          --
--  This library is distributed in the hope that it will be useful, but     --
--  WITHOUT ANY WARRANTY; without even the implied warranty of              --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       --
--  General Public License for more details.                                --
--                                                                          --
--  You should have received a copy of the GNU General Public License       --
--  along with this library; if not, write to the Free Software Foundation, --
--  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.          --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

--  $Id$

with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.Calendar.Time_IO;

with AWS;
with AWS.OS_Lib;
with AWS.Templates;
with AWS.Utils;
with SOAP.Utils;
with SOAP.WSDL.Parameters;

package body SOAP.Generator is

   use Ada;
   use Ada.Exceptions;
   use Ada.Strings.Unbounded;

   function Format_Name (O : in Object; Name : in String) return String;
   --  Returns Name formated with the Ada style if O.Ada_Style is true and
   --  Name unchanged otherwise.

   function Time_Stamp return String;
   --  Returns a time stamp Ada comment line

   function Version_String return String;
   --  Returns a version string Ada comment line

   procedure Put_File_Header (O : in Object; File : in Text_IO.File_Type);
   --  Add a standard file header into file.

   procedure Put_Types
     (O      : in Object;
      Proc   : in String;
      Input  : in WSDL.Parameters.P_Set;
      Output : in WSDL.Parameters.P_Set);
   --  This must be called to create the data types for composite objects

   type Header_Mode is (Stub_Spec, Stub_Body, Skel_Spec, Skel_Body);

   subtype Stub_Header is Header_Mode range Stub_Spec .. Stub_Body;

   procedure Put_Header
     (File   : in Text_IO.File_Type;
      O      : in Object;
      Proc   : in String;
      Input  : in WSDL.Parameters.P_Set;
      Output : in WSDL.Parameters.P_Set;
      Mode   : in Header_Mode);
   --  Output procedure header into File. The terminating ';' or 'is' is
   --  outputed depending on Spec value.

   function Result_Type
     (O      : in Object;
      Proc   : in String;
      Output : in WSDL.Parameters.P_Set)
      return String;
   --  Returns the result type given the output parameters

   procedure Header_Box
     (O    : in Object;
      File : in Text_IO.File_Type;
      Name : in String);
   --  Generate header box

   function To_Unit_Name (Filename : in String) return String;
   --  Returns the unit name given a filename following the GNAT
   --  naming scheme.

   Root     : Text_IO.File_Type; -- Parent packages
   Type_Ads : Text_IO.File_Type; -- Child with all type definitions
   Type_Adb : Text_IO.File_Type;
   Stub_Ads : Text_IO.File_Type; -- Child with client interface
   Stub_Adb : Text_IO.File_Type;
   Skel_Ads : Text_IO.File_Type; -- Child with server interface
   Skel_Adb : Text_IO.File_Type;
   CB_Ads   : Text_IO.File_Type; -- Child with all callback routines
   CB_Adb   : Text_IO.File_Type;
   Tmp_Adb  : Text_IO.File_Type; -- Temporary files with callback definitions

   --  Stub generator routines

   package Stub is

      procedure Start_Service
        (O             : in out Object;
         Name          : in     String;
         Documentation : in     String;
         Location      : in     String);

      procedure End_Service
        (O    : in out Object;
         Name : in     String);

      procedure New_Procedure
        (O          : in out Object;
         Proc       : in     String;
         SOAPAction : in     String;
         Namespace  : in     String;
         Input      : in     WSDL.Parameters.P_Set;
         Output     : in     WSDL.Parameters.P_Set;
         Fault      : in     WSDL.Parameters.P_Set);

   end Stub;

   --  Skeleton generator routines

   package Skel is

      procedure Start_Service
        (O             : in out Object;
         Name          : in     String;
         Documentation : in     String;
         Location      : in     String);

      procedure End_Service
        (O    : in out Object;
         Name : in     String);

      procedure New_Procedure
        (O          : in out Object;
         Proc       : in     String;
         SOAPAction : in     String;
         Namespace  : in     String;
         Input      : in     WSDL.Parameters.P_Set;
         Output     : in     WSDL.Parameters.P_Set;
         Fault      : in     WSDL.Parameters.P_Set);

   end Skel;

   --  Callback generator routines

   package CB is

      procedure Start_Service
        (O             : in out Object;
         Name          : in     String;
         Documentation : in     String;
         Location      : in     String);

      procedure End_Service
        (O    : in out Object;
         Name : in     String);

      procedure New_Procedure
        (O          : in out Object;
         Proc       : in     String;
         SOAPAction : in     String;
         Namespace  : in     String;
         Input      : in     WSDL.Parameters.P_Set;
         Output     : in     WSDL.Parameters.P_Set;
         Fault      : in     WSDL.Parameters.P_Set);

   end CB;

   --  Simple name set used to keep record of all generated types

   package Name_Set is

      procedure Add (Name : in String);
      --  Add new name into the set

      function Exists (Name : in String) return Boolean;
      --  Returns true if Name is in the set

   end Name_Set;

   ---------------
   -- Ada_Style --
   ---------------

   procedure Ada_Style (O : in out Object) is
   begin
      O.Ada_Style := True;
   end Ada_Style;

   --------
   -- CB --
   --------

   package body CB is separate;

   -------------
   -- CVS_Tag --
   -------------

   procedure CVS_Tag (O : in out Object) is
   begin
      O.CVS_Tag := True;
   end CVS_Tag;

   -----------
   -- Debug --
   -----------

   procedure Debug (O : in out Object) is
   begin
      O.Debug := True;
   end Debug;

   -----------------
   -- End_Service --
   -----------------

   procedure End_Service
     (O    : in out Object;
      Name : in     String)
   is
      U_Name  : constant String := To_Unit_Name (Format_Name (O, Name));
   begin
      --  Root

      Text_IO.New_Line (Root);
      Text_IO.Put_Line (Root, "end " & U_Name & ";");

      Text_IO.Close (Root);

      --  Types

      Text_IO.New_Line (Type_Ads);
      Text_IO.Put_Line (Type_Ads, "end " & U_Name & ".Types;");

      Text_IO.Close (Type_Ads);

      Text_IO.New_Line (Type_Adb);
      Text_IO.Put_Line (Type_Adb, "end " & U_Name & ".Types;");

      Text_IO.Close (Type_Adb);

      --  Stub

      if O.Gen_Stub then
         Stub.End_Service (O, Name);
         Text_IO.Close (Stub_Ads);
         Text_IO.Close (Stub_Adb);
      end if;

      --  Skeleton

      if O.Gen_Skel then
         Skel.End_Service (O, Name);
         Text_IO.Close (Skel_Ads);
         Text_IO.Close (Skel_Adb);
      end if;

      --  Callbacks

      if O.Gen_CB then
         CB.End_Service (O, Name);
         Text_IO.Close (CB_Ads);
         Text_IO.Close (CB_Adb);
         Text_IO.Close (Tmp_Adb);
      end if;
   end End_Service;

   -----------------
   -- Format_Name --
   -----------------

   function Format_Name (O : in Object; Name : in String) return String is

      function Ada_Format (Name : in String) return String;
      --  Returns Name with the Ada style

      function Ada_Format (Name : in String) return String is
         Result : Unbounded_String;
      begin
         --  No need to reformat this name
         if not O.Ada_Style then
            return Name;
         end if;

         for K in Name'Range loop
            if K = Name'First then
               Append (Result, Characters.Handling.To_Upper (Name (K)));

            elsif Characters.Handling.Is_Upper (Name (K))
              and then K > Name'First
              and then Name (K - 1) /= '_'
              and then Name (K - 1) /= '.'
              and then K < Name'Last
              and then Name (K + 1) /= '_'
              and then Name (K + 1) /= '.'
            then
               Append (Result, "_" & Name (K));

            else
               Append (Result, Name (K));
            end if;
         end loop;

         return To_String (Result);
      end Ada_Format;

      Ada_Name : constant String := Ada_Format (Name);

   begin
      if Utils.Is_Ada_Reserved_Word (Name) then
         return "v_" & Ada_Name;
      else
         return Ada_Name;
      end if;
   end Format_Name;

   ------------
   -- Gen_CB --
   ------------

   procedure Gen_CB (O : in out Object) is
   begin
      O.Gen_CB := True;
   end Gen_CB;

   ----------------
   -- Header_Box --
   ----------------

   procedure Header_Box
     (O    : in Object;
      File : in Text_IO.File_Type;
      Name : in String)
   is
      pragma Unreferenced (O);
   begin
      Text_IO.Put_Line
        (File, "   " & String'(1 .. 6 + Name'Length => '-'));
      Text_IO.Put_Line
        (File, "   -- " & Name & " --");
      Text_IO.Put_Line
        (File, "   " & String'(1 .. 6 + Name'Length => '-'));
   end Header_Box;

   ----------
   -- Main --
   ----------

   procedure Main (O : in out Object; Name : in String) is
   begin
      O.Main := To_Unbounded_String (Name);
   end Main;

   --------------
   -- Name_Set --
   --------------

   package body Name_Set is separate;

   -------------------
   -- New_Procedure --
   -------------------

   procedure New_Procedure
     (O          : in out Object;
      Proc       : in     String;
      SOAPAction : in     String;
      Namespace  : in     String;
      Input      : in     WSDL.Parameters.P_Set;
      Output     : in     WSDL.Parameters.P_Set;
      Fault      : in     WSDL.Parameters.P_Set) is
   begin
      if not O.Quiet then
         Text_IO.Put_Line ("   > " & Proc);
      end if;

      Put_Types (O, Proc, Input, Output);

      if O.Gen_Stub then
         Stub.New_Procedure
           (O, Proc, SOAPAction, Namespace, Input, Output, Fault);
      end if;

      if O.Gen_Skel then
         Skel.New_Procedure
           (O, Proc, SOAPAction, Namespace, Input, Output, Fault);
      end if;

      if O.Gen_CB then
         CB.New_Procedure
           (O, Proc, SOAPAction, Namespace, Input, Output, Fault);
      end if;
   end New_Procedure;

   -------------
   -- No_Skel --
   -------------

   procedure No_Skel (O : in out Object) is
   begin
      O.Gen_Skel := False;
   end No_Skel;

   -------------
   -- No_Stub --
   -------------

   procedure No_Stub (O : in out Object) is
   begin
      O.Gen_Stub := False;
   end No_Stub;

   -------------
   -- Options --
   -------------

   procedure Options (O : in out Object; Options : in String) is
   begin
      O.Options := To_Unbounded_String (Options);
   end Options;

   ---------------
   -- Overwrite --
   ---------------

   procedure Overwrite (O : in out Object) is
   begin
      O.Force := True;
   end Overwrite;

   ---------------------
   -- Put_File_Header --
   ---------------------

   procedure Put_File_Header (O : in Object; File : in Text_IO.File_Type) is
   begin
      Text_IO.New_Line (File);
      Text_IO.Put_Line (File, "--  wsdl2aws SOAP Generator v" & Version);
      Text_IO.Put_Line (File, "--");
      Text_IO.Put_Line (File, Version_String);
      Text_IO.Put_Line (File, Time_Stamp);
      Text_IO.Put_Line (File, "--");
      Text_IO.Put_Line (File, "--  $ wsdl2aws " & To_String (O.Options));
      Text_IO.New_Line (File);

      if O.CVS_Tag then
         Text_IO.Put_Line (File, "--  $" & "Id$");
         Text_IO.New_Line (File);
      end if;
   end Put_File_Header;

   ----------------
   -- Put_Header --
   ----------------

   procedure Put_Header
     (File   : in Text_IO.File_Type;
      O      : in Object;
      Proc   : in String;
      Input  : in WSDL.Parameters.P_Set;
      Output : in WSDL.Parameters.P_Set;
      Mode   : in Header_Mode)
   is
      use Ada.Strings.Fixed;
      use type SOAP.WSDL.Parameters.P_Set;
      use type SOAP.WSDL.Parameters.Kind;

      procedure Put_Indent (Last : in Character := ' ');
      --  Ouput proper indentation spaces

      ----------------
      -- Put_Indent --
      ----------------

      procedure Put_Indent (Last : in Character := ' ') is
      begin
         if Mode = Skel_Spec then
            Text_IO.Put (File, "   ");
         end if;
         Text_IO.Put (File, "     " & Last);
      end Put_Indent;

      L_Proc  : constant String := Format_Name (O, Proc);
      Max_Len : Positive := 8;

      N       : WSDL.Parameters.P_Set;
   begin
      --  Compute maximum name length
      N := Input;

      while N /= null loop
         Max_Len := Positive'Max
           (Max_Len, Format_Name (O, To_String (N.Name))'Length);
         N := N.Next;
      end loop;

      --  Ouput header

      if Output = null then
         Text_IO.Put (File, "procedure " & L_Proc);

         if Mode in Stub_Header or else Input /= null then
            Text_IO.New_Line (File);
         end if;

      else
         Text_IO.Put_Line (File, "function " & L_Proc);
      end if;

      --  Input parameters

      if Input /= null or else Mode in Stub_Header then
         Put_Indent ('(');
      end if;

      if Input /= null then
         --  Output parameters

         N := Input;

         while N /= null loop
            declare
               Name : constant String
                 := Format_Name (O, To_String (N.Name));
            begin
               Text_IO.Put (File, Name);
               Text_IO.Put (File, (Max_Len - Name'Length) * ' ');
            end;

            Text_IO.Put (File, " : in ");

            case N.Mode is
               when WSDL.Parameters.K_Simple =>
                  Text_IO.Put (File, WSDL.To_Ada (N.P_Type));

               when WSDL.Parameters.K_Derived =>
                  Text_IO.Put (File, To_String (N.D_Name) & "_Type");

               when WSDL.Parameters.K_Enumeration =>
                  Text_IO.Put (File, To_String (N.E_Name) & "_Type");

               when WSDL.Parameters.K_Record | WSDL.Parameters.K_Array =>
                  Text_IO.Put
                    (File, Format_Name (O, To_String (N.T_Name) & "_Type"));
            end case;

            if N.Next /= null then
               Text_IO.Put_Line (File, ";");
               Put_Indent;
            end if;

            N := N.Next;
         end loop;
      end if;

      if Mode in Stub_Header then
         if Input /= null then
            Text_IO.Put_Line (File, ";");
            Put_Indent;
         end if;

         Text_IO.Put (File, "Endpoint");
         Text_IO.Put (File, (Max_Len - 8) * ' ');
         Text_IO.Put
           (File, " : in String := " & To_String (O.Unit) & ".URL");
      end if;

      if Input /= null or else Mode in Stub_Header then
         Text_IO.Put (File, ")");
      end if;

      --  Output parameters

      if Output /= null then

         if Input /= null then
            Text_IO.New_Line (File);
         end if;

         Put_Indent;
         Text_IO.Put (File, "return ");

         Text_IO.Put (File, Result_Type (O, Proc, Output));
      end if;

      --  End header depending on the mode

      case Mode is
         when Stub_Spec | Skel_Spec =>
            Text_IO.Put_Line (File, ";");

         when Stub_Body =>
            Text_IO.New_Line (Stub_Adb);
            Text_IO.Put_Line (Stub_Adb, "   is");

         when Skel_Body =>
            null;
      end case;
   end Put_Header;

   ---------------
   -- Put_Types --
   ---------------

   procedure Put_Types
     (O      : in Object;
      Proc   : in String;
      Input  : in WSDL.Parameters.P_Set;
      Output : in WSDL.Parameters.P_Set)
   is
      use type WSDL.Parameters.Kind;
      use type WSDL.Parameters.P_Set;

      procedure Generate_Record
        (Name   : in String;
         P      : in WSDL.Parameters.P_Set;
         Output : in Boolean               := False);
      --  Output record definitions (type and routine conversion)

      function Type_Name (N : in WSDL.Parameters.P_Set) return String;
      --  Returns the name of the type for parameter on node N

      procedure Generate_Array
        (Name : in String;
         P    : in WSDL.Parameters.P_Set);
      --  Generate array definitions (type and routine conversion)

      procedure Generate_Derived
        (Name : in String;
         P    : in WSDL.Parameters.P_Set);
      --  Generate derived type definition

      procedure Generate_Enumeration
        (Name : in String;
         P    : in WSDL.Parameters.P_Set);
      --  Generate enumeration type definition

      procedure Generate_Safe_Array
        (Name : in String;
         P    : in WSDL.Parameters.P_Set);
      --  Generate the safe array runtime support. This is only done when a
      --  user spec is speficied. We must generate such reference to user's
      --  spec only if we have an array inside a record.

      procedure Output_Types (P : in WSDL.Parameters.P_Set);
      --  Output types conversion routines

      function Get_Routine (P : in WSDL.Parameters.P_Set) return String;
      --  Returns the Get routine for the given type

      function Set_Routine (P : in WSDL.Parameters.P_Set) return String;
      --  Returns the constructor routine for the given type

      function Set_Type (Name : in String) return String;
      --  Returns the SOAP type for Name

      function Is_Inside_Record (Name : in String) return Boolean;
      --  Returns True if Name is defined inside a record in the Input
      --  or Output parameter list.

      --------------------
      -- Generate_Array --
      --------------------

      procedure Generate_Array
        (Name : in String;
         P    : in WSDL.Parameters.P_Set)
      is

         function To_Ada_Type (Name : in String) return String;
         --  Returns the Ada corresponding type

         -----------------
         -- To_Ada_Type --
         -----------------

         function To_Ada_Type (Name : in String) return String is
         begin
            if WSDL.Is_Standard (Name) then
               return WSDL.To_Ada
                 (WSDL.To_Type (Name), Context => WSDL.Component);

            else
               return Format_Name (O, Name) & "_Type";
            end if;
         end To_Ada_Type;

         F_Name : constant String := Format_Name (O, Name);

         T_Name : constant String := To_String (P.E_Type);

      begin
         Text_IO.New_Line (Type_Ads);
         Text_IO.Put_Line
           (Type_Ads, "   " & String'(1 .. 12 + F_Name'Length => '-'));
         Text_IO.Put_Line
           (Type_Ads, "   -- Array " & F_Name & " --");
         Text_IO.Put_Line
           (Type_Ads, "   " & String'(1 .. 12 + F_Name'Length => '-'));

         Text_IO.New_Line (Type_Ads);

         --  Is types are to be reused from an Ada  spec ?

         if O.Types_Spec = Null_Unbounded_String then
            --  No user's spec, generate all typ definitions

            --  Array type

            if P.Length = 0 then
               --  Unconstrained array
               Text_IO.Put_Line
                 (Type_Ads,
                  "   type " & F_Name & " is array (Positive range <>) of "
                    & To_Ada_Type (T_Name) & ";");
            else
               --  A constrained array

               Text_IO.Put_Line
                 (Type_Ads,
                  "   subtype " & F_Name & "_Index is Positive range 1 .. "
                    & AWS.Utils.Image (P.Length) & ";");
               Text_IO.New_Line (Type_Ads);
               Text_IO.Put_Line
                 (Type_Ads,
                  "   type " & F_Name & " is array (" & F_Name & "_Index)"
                    & " of " & To_Ada_Type (T_Name) & ";");
            end if;

            --  Access to it

            --  Safe pointer, needed only for unconstrained arrays

            if P.Length = 0 then
               Text_IO.Put_Line
                 (Type_Ads, "   type "
                    & F_Name & "_Access" & " is access all " & F_Name & ';');

               Text_IO.New_Line (Type_Ads);
               Text_IO.Put_Line
                 (Type_Ads, "   package " & F_Name & "_Safe_Pointer is");
               Text_IO.Put_Line
                 (Type_Ads, "      new SOAP.Utils.Safe_Pointers ("
                    & F_Name & ", " & F_Name & "_Access);");

               Text_IO.New_Line (Type_Ads);
               Text_IO.Put_Line
                 (Type_Ads, "   subtype " & F_Name & "_Safe_Access");
               Text_IO.Put_Line
                 (Type_Ads, "      is " & F_Name
                    & "_Safe_Pointer.Safe_Pointer;");

               Text_IO.New_Line (Type_Ads);
               Text_IO.Put_Line
                 (Type_Ads, "   function ""+""");
               Text_IO.Put_Line
                 (Type_Ads, "     (O : in " & F_Name & ')');
               Text_IO.Put_Line
                 (Type_Ads, "      return " & F_Name & "_Safe_Access");
               Text_IO.Put_Line
                 (Type_Ads, "      renames " & F_Name
                    & "_Safe_Pointer.To_Safe_Pointer;");
               Text_IO.Put_Line
                 (Type_Ads, "   --  Convert an array to a safe pointer");
            end if;

         else
            --  Here we have a reference to a spec, just build alias to it

            if P.Length /= 0 then
               --  This is a constrained array, create the index subtype
               Text_IO.Put_Line
                 (Type_Ads,
                  "   subtype " & F_Name & "_Index is Positive range 1 .. "
                    & AWS.Utils.Image (P.Length) & ";");
            end if;

            Text_IO.Put_Line
              (Type_Ads, "   subtype " & F_Name & " is "
                 & To_String (O.Types_Spec)
                 & "." & To_String (P.T_Name) & ";");

            --  Note that we can't generate safe array runtime support at this
            --  point. It could be the case that this array is not inside a
            --  record but another reference in the WSDL document will be
            --  inside a record. As a type is analyzed only once we must
            --  deferred this code generation. See Generate_Safe_Array.
         end if;

         Text_IO.New_Line (Type_Ads);

         if P.Length = 0 then
            Text_IO.Put_Line
              (Type_Ads, "   function To_" & F_Name
                 & " is new SOAP.Utils.To_T_Array");
         else
            Text_IO.Put_Line
              (Type_Ads, "   function To_" & F_Name
                 & " is new SOAP.Utils.To_T_Array_C");
         end if;

         Text_IO.Put
           (Type_Ads, "     (" & To_Ada_Type (T_Name) & ", ");

         if P.Length = 0 then
            Text_IO.Put (Type_Ads, F_Name);
         else
            Text_IO.Put (Type_Ads, F_Name & "_Index, " & F_Name);
         end if;

         Text_IO.Put_Line (Type_Ads, ", " & Get_Routine (P) & ");");

         Text_IO.New_Line (Type_Ads);

         if P.Length = 0 then
            Text_IO.Put_Line
              (Type_Ads, "   function To_Object_Set"
                 & " is new SOAP.Utils.To_Object_Set");
         else
            Text_IO.Put_Line
              (Type_Ads, "   function To_Object_Set"
                 & " is new SOAP.Utils.To_Object_Set_C");
         end if;

         Text_IO.Put
           (Type_Ads, "     (" & To_Ada_Type (T_Name) & ", ");

         if P.Length = 0 then
            Text_IO.Put_Line (Type_Ads, F_Name & ",");
         else
            Text_IO.Put_Line (Type_Ads, F_Name & "_Index, " & F_Name & ",");
         end if;

         Text_IO.Put_Line
           (Type_Ads,
            "      " & Set_Type (T_Name) & ", " & Set_Routine (P) & ");");
      end Generate_Array;

      ----------------------
      -- Generate_Derived --
      ----------------------

      procedure Generate_Derived
        (Name : in String;
         P    : in WSDL.Parameters.P_Set)
      is
         F_Name : constant String := Format_Name (O, Name);
         T_Name : constant String := WSDL.To_Ada (P.Parent_Type);
      begin
         Text_IO.New_Line (Type_Ads);

         --  Is types are to be reused from an Ada  spec ?

         if O.Types_Spec = Null_Unbounded_String then
            Text_IO.Put_Line
              (Type_Ads, "   type " & F_Name
                 & " is new " & T_Name & ";");
         else
            Text_IO.Put_Line
              (Type_Ads, "   subtype " & F_Name & " is "
                 & To_String (O.Types_Spec)
                 & "." & To_String (P.D_Name) & ";");
         end if;
      end Generate_Derived;

      --------------------------
      -- Generate_Enumeration --
      --------------------------

      procedure Generate_Enumeration
        (Name : in String;
         P    : in WSDL.Parameters.P_Set)
      is
         use type WSDL.Parameters.E_Node_Access;

         F_Name : constant String := Format_Name (O, Name);

         function Image (E : in WSDL.Parameters.E_Node_Access) return String;
         --  Returns the enumeration definition

         -----------
         -- Image --
         -----------

         function Image (E : in WSDL.Parameters.E_Node_Access) return String is
            Result : Unbounded_String;
            N      : WSDL.Parameters.E_Node_Access := E;
         begin
            while N /= null loop

               if Result = Null_Unbounded_String then
                  Append (Result, "(");
               else
                  Append (Result, ", ");
               end if;

               Append (Result, To_String (N.Value));

               N := N.Next;
            end loop;

            Append (Result, ")");

            return To_String (Result);
         end Image;

         N : WSDL.Parameters.E_Node_Access := P.E_Def;
      begin
         Text_IO.New_Line (Type_Ads);

         --  Is types are to be reused from an Ada  spec ?

         if O.Types_Spec = Null_Unbounded_String then
            Text_IO.Put_Line
              (Type_Ads, "   type " & F_Name
                 & " is " & Image (P.E_Def) & ";");
         else
            Text_IO.Put_Line
              (Type_Ads, "   subtype " & F_Name & " is "
                 & To_String (O.Types_Spec)
                 & "." & To_String (P.E_Name) & ";");
         end if;

         --  Generate Image function

         Text_IO.New_Line (Type_Ads);
         Text_IO.Put_Line
           (Type_Ads,
            "   function Image (E : in " & F_Name & ") return String;");

         Text_IO.New_Line (Type_Adb);
         Text_IO.Put_Line
           (Type_Adb,
            "   function Image (E : in " & F_Name & ") return String is");
         Text_IO.Put_Line (Type_Adb, "   begin");
         Text_IO.Put_Line (Type_Adb, "      case E is");

         while N /= null loop
            Text_IO.Put (Type_Adb, "         when ");

            if O.Types_Spec /= Null_Unbounded_String then
               Text_IO.Put (Type_Adb, To_String (O.Types_Spec) & '.');
            end if;

            Text_IO.Put_Line
              (Type_Adb, To_String (N.Value)
                 & " => return """ & To_String (N.Value) & """;");

            N := N.Next;
         end loop;

         Text_IO.Put_Line (Type_Adb, "      end case;");
         Text_IO.Put_Line (Type_Adb, "   end Image;");
      end Generate_Enumeration;

      ---------------------
      -- Generate_Record --
      ---------------------

      procedure Generate_Record
        (Name   : in String;
         P      : in WSDL.Parameters.P_Set;
         Output : in Boolean               := False)
      is
         F_Name : constant String := Format_Name (O, Name);

         R   : WSDL.Parameters.P_Set;
         N   : WSDL.Parameters.P_Set;

         Max : Positive;

      begin
         if Output then
            R := P;
         else
            R := P.P;
         end if;

         --  Generate record type

         Text_IO.New_Line (Type_Ads);
         Header_Box (O, Type_Ads, "Record " & F_Name);

         --  Is types are to be reused from an Ada spec ?

         if O.Types_Spec = Null_Unbounded_String then

            --  Compute max field width

            N := R;

            Max := 1;

            while N /= null loop
               Max := Positive'Max
                 (Max, Format_Name (O, To_String (N.Name))'Length);
               N := N.Next;
            end loop;

            --  Output field

            N := R;

            Text_IO.New_Line (Type_Ads);
            Text_IO.Put_Line
              (Type_Ads, "   type " & F_Name & " is record");

            while N /= null loop
               declare
                  F_Name : constant String
                    := Format_Name (O, To_String (N.Name));
               begin
                  Text_IO.Put
                    (Type_Ads, "      "
                       & F_Name
                       & String'(1 .. Max - F_Name'Length => ' ') & " : ");
               end;

               Text_IO.Put (Type_Ads, Format_Name (O, Type_Name (N)));

               Text_IO.Put_Line (Type_Ads, ";");

               if N.Mode = WSDL.Parameters.K_Array then
                  Text_IO.Put_Line
                    (Type_Ads,
                     "      --  Access items with : result.Item (n)");
               end if;

               N := N.Next;
            end loop;

            Text_IO.Put_Line
              (Type_Ads, "   end record;");

         else
            Text_IO.New_Line (Type_Ads);
            Text_IO.Put_Line
              (Type_Ads, "   subtype " & F_Name & " is "
                 & To_String (O.Types_Spec)
                 & "." & To_String (P.T_Name) & ";");
         end if;

         --  Generate conversion spec

         Text_IO.New_Line (Type_Ads);
         Text_IO.Put_Line (Type_Ads, "   function To_" & F_Name);

         Text_IO.Put_Line (Type_Ads, "     (O : in SOAP.Types.Object'Class)");
         Text_IO.Put_Line (Type_Ads, "      return " & F_Name & ';');

         Text_IO.New_Line (Type_Ads);
         Text_IO.Put_Line (Type_Ads, "   function To_SOAP_Object");

         Text_IO.Put_Line (Type_Ads, "     (R    : in " & F_Name & ';');
         Text_IO.Put_Line (Type_Ads, "      Name : in String := ""item"")");
         Text_IO.Put_Line (Type_Ads, "      return SOAP.Types.SOAP_Record;");

         --  Generate conversion body

         Text_IO.New_Line (Type_Adb);
         Header_Box (O, Type_Adb, "Record " & F_Name);

         --  SOAP to Ada

         Text_IO.New_Line (Type_Adb);
         Text_IO.Put_Line (Type_Adb, "   function To_" & F_Name);

         Text_IO.Put_Line (Type_Adb, "     (O : in SOAP.Types.Object'Class)");
         Text_IO.Put_Line (Type_Adb, "      return " & F_Name);
         Text_IO.Put_Line (Type_Adb, "   is");
         Text_IO.Put_Line
           (Type_Adb,
            "      R : constant SOAP.Types.SOAP_Record "
              & ":= SOAP.Types.SOAP_Record (O);");

         N := R;

         while N /= null loop
            case N.Mode is
               when WSDL.Parameters.K_Simple =>
                  declare
                     I_Type : constant String := WSDL.Set_Type (N.P_Type);
                  begin
                     Text_IO.Put_Line
                       (Type_Adb,
                        "      " & Format_Name (O, To_String (N.Name))
                          & " : constant " & I_Type);
                     Text_IO.Put_Line
                       (Type_Adb,
                        "         := " & I_Type & " (SOAP.Types.V (R, """
                          & To_String (N.Name) & """));");
                  end;

               when WSDL.Parameters.K_Derived =>
                  declare
                     I_Type : constant String := WSDL.Set_Type (N.Parent_Type);
                  begin
                     Text_IO.Put_Line
                       (Type_Adb,
                        "      " & Format_Name (O, To_String (N.Name))
                          & " : constant " & I_Type);
                     Text_IO.Put_Line
                       (Type_Adb,
                        "         := " & I_Type & " (SOAP.Types.V (R, """
                          & To_String (N.Name) & """));");
                  end;

               when WSDL.Parameters.K_Enumeration =>
                  Text_IO.Put_Line
                    (Type_Adb,
                     "      " & Format_Name (O, To_String (N.Name))
                       & " : constant SOAP.Types.SOAP_Enumeration");
                  Text_IO.Put_Line
                    (Type_Adb,
                     "         := SOAP.Types.SOAP_Enumeration (SOAP.Types.V "
                       & "(R, """ & To_String (N.Name) & """));");

               when WSDL.Parameters.K_Array =>
                  Text_IO.Put_Line
                    (Type_Adb,
                     "      " & Format_Name (O, To_String (N.Name))
                       & " : constant SOAP.Types.SOAP_Array");
                  Text_IO.Put_Line
                    (Type_Adb,
                     "         := SOAP.Types.SOAP_Array (SOAP.Types.V (R, """
                       & To_String (N.Name) & """));");

               when WSDL.Parameters.K_Record =>
                  Text_IO.Put_Line
                    (Type_Adb,
                     "      " & Format_Name (O, To_String (N.Name))
                       & " : constant SOAP.Types.SOAP_Record");
                  Text_IO.Put_Line
                    (Type_Adb,
                     "         := SOAP.Types.SOAP_Record (SOAP.Types.V (R, """
                       & To_String (N.Name) & """));");
            end case;

            N := N.Next;
         end loop;

         Text_IO.Put_Line (Type_Adb, "   begin");
         Text_IO.Put      (Type_Adb, "      return (");

         N := R;

         if N.Next = null then
            --  We have a single element into this record, we must use a named
            --  notation for the aggregate.
            Text_IO.Put (Type_Adb, To_String (N.Name) & " => ");
         end if;

         while N /= null loop

            if N /= R then
               Text_IO.Put      (Type_Adb, "              ");
            end if;

            case N.Mode is
               when WSDL.Parameters.K_Simple =>
                  Text_IO.Put
                    (Type_Adb, WSDL.V_Routine (N.P_Type, WSDL.Component)
                       & " (" & Format_Name (O, To_String (N.Name)) & ')');

               when WSDL.Parameters.K_Derived =>
                  Text_IO.Put
                    (Type_Adb,
                     To_String (N.D_Name) & "_Type ("
                       & WSDL.V_Routine (N.Parent_Type, WSDL.Component)
                       & " (" & Format_Name (O, To_String (N.Name)) & "))");

               when WSDL.Parameters.K_Enumeration =>
                  Text_IO.Put
                    (Type_Adb,
                     To_String (N.E_Name) & "_Type'Value ("
                       & "SOAP.Types.V ("
                       & Format_Name (O, To_String (N.Name)) & "))");

               when WSDL.Parameters.K_Array =>
                  Text_IO.Put
                    (Type_Adb, "+To_" & Format_Name (O, To_String (N.T_Name))
                       & "_Type (SOAP.Types.V ("
                       & Format_Name (O, To_String (N.Name)) & "))");

               when WSDL.Parameters.K_Record =>
                  Text_IO.Put (Type_Adb, Get_Routine (N));

                  Text_IO.Put
                    (Type_Adb,
                     " (" & Format_Name (O, To_String (N.Name)) & ")");
            end case;

            if N.Next = null then
               Text_IO.Put_Line (Type_Adb, ");");
            else
               Text_IO.Put_Line (Type_Adb, ",");
            end if;

            N := N.Next;
         end loop;

         Text_IO.Put_Line (Type_Adb, "   end To_" & F_Name & ';');

         --  To_SOAP_Object

         Text_IO.New_Line (Type_Adb);
         Text_IO.Put_Line (Type_Adb, "   function To_SOAP_Object");

         Text_IO.Put_Line (Type_Adb, "     (R : in " & F_Name & ';');
         Text_IO.Put_Line (Type_Adb, "      Name : in String := ""item"")");
         Text_IO.Put_Line (Type_Adb, "      return SOAP.Types.SOAP_Record");
         Text_IO.Put_Line (Type_Adb, "   is");
         Text_IO.Put_Line (Type_Adb, "      Result : SOAP.Types.SOAP_Record;");
         Text_IO.Put_Line (Type_Adb, "   begin");

         N := R;

         Text_IO.Put_Line (Type_Adb, "      Result := SOAP.Types.R");

         while N /= null loop

            if N = R then

               if R.Next = null then
                  --  We have a single element into this record, we must use a
                  --  named notation for the aggregate.
                  Text_IO.Put (Type_Adb, "        ((1 => +");
               else
                  Text_IO.Put (Type_Adb, "        ((+");
               end if;

            else
               Text_IO.Put      (Type_Adb, "          +");
            end if;

            case N.Mode is
               when WSDL.Parameters.K_Simple =>
                  Text_IO.Put (Type_Adb, Set_Routine (N));

                  Text_IO.Put
                    (Type_Adb,
                     " (R." & Format_Name (O, To_String (N.Name))
                       & ", """ & To_String (N.Name) & """)");

               when WSDL.Parameters.K_Derived =>
                  Text_IO.Put (Type_Adb, Set_Routine (N));

                  Text_IO.Put
                    (Type_Adb,
                     " (" & WSDL.To_Ada (N.Parent_Type)
                       & " (R." & Format_Name (O, To_String (N.Name))
                       & "), """ & To_String (N.Name) & """)");

               when WSDL.Parameters.K_Enumeration =>
                  Text_IO.Put
                    (Type_Adb,
                     " SOAP.Types.E (Image"
                       & " (R." & Format_Name (O, To_String (N.Name))
                       & "), """ & To_String (N.E_Name)
                       & """, """ & To_String (N.Name) & """)");

               when WSDL.Parameters.K_Array =>
                  Text_IO.Put
                    (Type_Adb,
                     "SOAP.Types.A (To_Object_Set (R."
                       & Format_Name (O, To_String (N.Name))
                       & ".Item.all), """ & To_String (N.Name) & """)");

               when WSDL.Parameters.K_Record =>
                  Text_IO.Put (Type_Adb, Set_Routine (N));

                  Text_IO.Put
                    (Type_Adb,
                     " (R." & Format_Name (O, To_String (N.Name))
                       & ", """ & To_String (N.Name) & """)");
            end case;

            if N.Next = null then
               Text_IO.Put_Line (Type_Adb, "),");
            else
               Text_IO.Put_Line (Type_Adb, ",");
            end if;

            N := N.Next;
         end loop;

         Text_IO.Put_Line
           (Type_Adb,
            "         Name, """ & To_String (P.T_Name) & """);");

         Text_IO.Put_Line (Type_Adb, "      return Result;");
         Text_IO.Put_Line (Type_Adb, "   end To_SOAP_Object;");
      end Generate_Record;

      -------------------------
      -- Generate_Safe_Array --
      -------------------------

      procedure Generate_Safe_Array
        (Name : in String;
         P    : in WSDL.Parameters.P_Set)
      is
         F_Name : constant String := Format_Name (O, Name) & "_Type";
      begin
         if O.Types_Spec /= Null_Unbounded_String
           and then Is_Inside_Record (Name)
           and then not Name_Set.Exists (Name & "Safe_Array_Support__")
         then
            --  Only if we have a user's spec specificed and this array is
            --  inside a record and we don't have generated this support.

            Name_Set.Add (Name & "Safe_Array_Support__");

            Text_IO.New_Line (Type_Ads);

            Header_Box (O, Type_Ads, "Safe Array " & F_Name);

            Text_IO.New_Line (Type_Ads);
            Text_IO.Put_Line
              (Type_Ads, "   subtype " & F_Name & "_Safe_Access");
            Text_IO.Put_Line
              (Type_Ads, "      is " & To_String (O.Types_Spec) & "."
                 & To_String (P.T_Name) & "_Safe_Pointer.Safe_Pointer;");

            Text_IO.New_Line (Type_Ads);
            Text_IO.Put_Line
              (Type_Ads, "   function ""+""");
            Text_IO.Put_Line
              (Type_Ads, "     (O : in " & F_Name & ')');
            Text_IO.Put_Line
              (Type_Ads, "      return " & F_Name & "_Safe_Access");
            Text_IO.Put_Line
              (Type_Ads, "      renames " & To_String (O.Types_Spec) & "."
                 & To_String (P.T_Name) & "_Safe_Pointer.To_Safe_Pointer;");
            Text_IO.Put_Line
              (Type_Ads, "   --  Convert an array to a safe pointer");
         end if;
      end Generate_Safe_Array;

      -----------------
      -- Get_Routine --
      -----------------

      function Get_Routine (P : in WSDL.Parameters.P_Set) return String is
      begin
         case P.Mode is
            when WSDL.Parameters.K_Simple =>
               return WSDL.Get_Routine (P.P_Type);

            when WSDL.Parameters.K_Derived =>
               return WSDL.Get_Routine (P.Parent_Type);

            when WSDL.Parameters.K_Enumeration =>
               return WSDL.Get_Routine (WSDL.P_String);

            when WSDL.Parameters.K_Array =>
               declare
                  T_Name : constant String := To_String (P.E_Type);
               begin
                  if WSDL.Is_Standard (T_Name) then
                     return WSDL.Get_Routine
                       (WSDL.To_Type (T_Name), WSDL.Component);
                  else
                     return "To_" & Format_Name (O, T_Name) & "_Type";
                  end if;
               end;

            when WSDL.Parameters.K_Record =>
               return "To_" & Type_Name (P);
         end case;
      end Get_Routine;

      ----------------------
      -- Is_Inside_Record --
      ----------------------

      function Is_Inside_Record (Name : in String) return Boolean is

         use type WSDL.Parameters.Kind;

         In_Record : Boolean := False;

         procedure Check_Record
           (P_Set : in     WSDL.Parameters.P_Set;
            Mode  :    out Boolean);
         --  Checks all record fields for Name

         procedure Check_Parameters
           (P_Set : in WSDL.Parameters.P_Set);
         --  Checks P_Set for Name declared inside a record

         ----------------------
         -- Check_Parameters --
         ----------------------

         procedure Check_Parameters
           (P_Set : in WSDL.Parameters.P_Set)
         is
            P : WSDL.Parameters.P_Set := P_Set;
         begin
            while P /= null loop
               if P.Mode = WSDL.Parameters.K_Record then
                  Check_Record (P.P, In_Record);
               end if;

               P := P.Next;
            end loop;
         end Check_Parameters;

         ------------------
         -- Check_Record --
         ------------------

         procedure Check_Record
           (P_Set : in     WSDL.Parameters.P_Set;
            Mode  :    out Boolean)
         is
            P : WSDL.Parameters.P_Set := P_Set;
         begin
            while P /= null loop
               if P.Mode = WSDL.Parameters.K_Array
                 and then To_String (P.T_Name) = Name
               then
                  Mode := True;
               end if;

               if P.Mode = WSDL.Parameters.K_Record then
                  Check_Record (P.P, Mode);
               end if;

               P := P.Next;
            end loop;
         end Check_Record;

      begin
         Check_Parameters (Input);
         Check_Parameters (Output);

         return In_Record;
      end Is_Inside_Record;

      ------------------
      -- Output_Types --
      ------------------

      procedure Output_Types (P : in WSDL.Parameters.P_Set) is
         N : WSDL.Parameters.P_Set := P;
      begin
         while N /= null loop
            case N.Mode is
               when WSDL.Parameters.K_Simple =>
                  null;

               when WSDL.Parameters.K_Derived =>
                  declare
                     Name : constant String := To_String (N.D_Name);
                  begin
                     if not Name_Set.Exists (Name) then

                        Name_Set.Add (Name);

                        Generate_Derived (Name & "_Type", N);
                     end if;
                  end;

               when WSDL.Parameters.K_Enumeration =>
                  declare
                     Name : constant String := To_String (N.E_Name);
                  begin
                     if not Name_Set.Exists (Name) then

                        Name_Set.Add (Name);

                        Generate_Enumeration (Name & "_Type", N);
                     end if;
                  end;

               when WSDL.Parameters.K_Array =>

                  Output_Types (N.P);

                  declare
                     Name : constant String := To_String (N.T_Name);
                  begin
                     if not Name_Set.Exists (Name) then

                        Name_Set.Add (Name);

                        Generate_Array (Name & "_Type", N);
                     end if;

                     Generate_Safe_Array (Name, N);
                  end;

               when WSDL.Parameters.K_Record =>

                  Output_Types (N.P);

                  declare
                     Name : constant String := To_String (N.T_Name);
                  begin
                     if not Name_Set.Exists (Name) then

                        Name_Set.Add (Name);

                        Generate_Record (Name & "_Type", N);
                     end if;
                  end;
            end case;

            N := N.Next;
         end loop;
      end Output_Types;

      -----------------
      -- Set_Routine --
      -----------------

      function Set_Routine (P : in WSDL.Parameters.P_Set) return String is
      begin
         case P.Mode is
            when WSDL.Parameters.K_Simple =>
               return WSDL.Set_Routine (P.P_Type, Context => WSDL.Component);

            when WSDL.Parameters.K_Derived =>
               return WSDL.Set_Routine
                 (P.Parent_Type, Context => WSDL.Component);

            when WSDL.Parameters.K_Enumeration =>
               return WSDL.Set_Routine
                 (WSDL.P_String, Context => WSDL.Component);

            when WSDL.Parameters.K_Array =>
               declare
                  T_Name : constant String := To_String (P.E_Type);
               begin
                  if WSDL.Is_Standard (T_Name) then
                     return WSDL.Set_Routine
                       (WSDL.To_Type (T_Name), Context => WSDL.Component);
                  else
                     return "To_SOAP_Object";
                  end if;
               end;

            when WSDL.Parameters.K_Record =>
               return "To_SOAP_Object";
         end case;
      end Set_Routine;

      --------------
      -- Set_Type --
      --------------

      function Set_Type (Name : in String) return String is
      begin
         if WSDL.Is_Standard (Name) then
            return WSDL.Set_Type (WSDL.To_Type (Name));
         else
            return "SOAP.Types.SOAP_Record";
         end if;
      end Set_Type;

      ---------------
      -- Type_Name --
      ---------------

      function Type_Name (N : in WSDL.Parameters.P_Set) return String is
         use type WSDL.Parameter_Type;
      begin
         case N.Mode is
            when WSDL.Parameters.K_Simple =>
               --  This routine is called only for SOAP object in records
               --  or arrays.
               return WSDL.To_Ada (N.P_Type, Context => WSDL.Component);

            when WSDL.Parameters.K_Derived =>
               return Format_Name (O, To_String (N.D_Name)) & "_Type";

            when WSDL.Parameters.K_Enumeration =>
               return Format_Name (O, To_String (N.E_Name)) & "_Type";

            when WSDL.Parameters.K_Array =>
               return Format_Name (O, To_String (N.T_Name))
                 & "_Type_Safe_Access";

            when WSDL.Parameters.K_Record =>
               return Format_Name (O, To_String (N.T_Name)) & "_Type";
         end case;
      end Type_Name;

      L_Proc : constant String := Format_Name (O, Proc);

   begin
      Output_Types (Input);

      Output_Types (Output);

      if Output /= null then
         --  Output mode and more than one parameter

         if Output.Next = null then

            case Output.Mode is

               when WSDL.Parameters.K_Simple =>
                  null;

               when WSDL.Parameters.K_Derived =>
                  --  A single declaration, this is a derived type create a
                  --  subtype.

                  Text_IO.New_Line (Type_Ads);
                  Text_IO.Put_Line
                    (Type_Ads,
                     "   subtype " & L_Proc & "_Result is "
                       & Format_Name (O, To_String (Output.D_Name))
                       & "_Type;");


               when WSDL.Parameters.K_Enumeration =>
                  --  A single declaration, this is an enumeration type create
                  --  a subtype.

                  Text_IO.New_Line (Type_Ads);
                  Text_IO.Put_Line
                    (Type_Ads,
                     "   subtype " & L_Proc & "_Result is "
                       & Format_Name (O, To_String (Output.E_Name))
                       & "_Type;");


               when WSDL.Parameters.K_Record | WSDL.Parameters.K_Array =>
                  --  A single declaration, this is a composite type create
                  --  a subtype.

                  Text_IO.New_Line (Type_Ads);
                  Text_IO.Put_Line
                    (Type_Ads,
                     "   subtype " & L_Proc & "_Result is "
                       & Format_Name (O, To_String (Output.T_Name))
                       & "_Type;");
            end case;

         else
            Generate_Record (L_Proc & "_Result", Output, Output => True);
         end if;
      end if;
   end Put_Types;

   -----------
   -- Quiet --
   -----------

   procedure Quiet (O : in out Object) is
   begin
      O.Quiet := True;
   end Quiet;

   -----------------
   -- Result_Type --
   -----------------

   function Result_Type
     (O      : in Object;
      Proc   : in String;
      Output : in WSDL.Parameters.P_Set)
      return String
   is
      use type WSDL.Parameters.Kind;

      L_Proc : constant String := Format_Name (O, Proc);
   begin
      if WSDL.Parameters.Length (Output) = 1
        and then Output.Mode = WSDL.Parameters.K_Simple
      then
         return WSDL.To_Ada (Output.P_Type);
      else
         return L_Proc & "_Result";
      end if;
   end Result_Type;

   ---------------
   -- Set_Proxy --
   ---------------

   procedure Set_Proxy
     (O : in out Object; Proxy, User, Password : in String) is
   begin
      O.Proxy  := To_Unbounded_String (Proxy);
      O.P_User := To_Unbounded_String (User);
      O.P_Pwd  := To_Unbounded_String (Password);
   end Set_Proxy;

   ----------
   -- Skel --
   ----------

   package body Skel is separate;

   -------------------
   -- Start_Service --
   -------------------

   procedure Start_Service
     (O             : in out Object;
      Name          : in     String;
      Documentation : in     String;
      Location      : in     String)
   is
      U_Name : constant String := To_Unit_Name (Format_Name (O, Name));

      procedure Create (File : in out Text_IO.File_Type; Filename : in String);
      --  Create Filename, raise execption Generator_Error if the file already
      --  exists and overwrite mode not activated.

      procedure Generate_Main (Filename : in String);
      --  Generate the main server's procedure. Either the file exists and is
      --  a template use it to generate the main otherwise just generate a
      --  standard main procedure.

      ------------
      -- Create --
      ------------

      procedure Create
        (File     : in out Text_IO.File_Type;
         Filename : in     String) is
      begin
         if AWS.OS_Lib.Is_Regular_File (Filename) and then not O.Force then
            Raise_Exception
              (Generator_Error'Identity,
               "File " & Filename & " exists, activate overwrite mode.");
         else
            Text_IO.Create (File, Text_IO.Out_File, Filename);
         end if;
      end Create;

      -------------------
      -- Generate_Main --
      -------------------

      procedure Generate_Main (Filename : in String) is
         use Text_IO;
         use AWS;

         L_Filename        : constant String
           := Characters.Handling.To_Lower (Filename);

         Template_Filename : constant String := L_Filename & ".amt";

         File : Text_IO.File_Type;

      begin
         Create (File, L_Filename & ".adb");

         Put_File_Header (O, File);

         if AWS.OS_Lib.Is_Regular_File (Template_Filename) then
            --  Use template file
            declare
               Translations : Templates.Translate_Table
                 := (1 => Templates.Assoc ("SOAP_SERVICE", U_Name),
                     2 => Templates.Assoc ("SOAP_VERSION", SOAP.Version),
                     3 => Templates.Assoc ("AWS_VERSION",  AWS.Version),
                     4 => Templates.Assoc ("UNIT_NAME",
                                           To_Unit_Name (Filename)));
            begin
               Put (File,
                    Templates.Parse (Template_Filename, Translations));
            end;

         else
            --  Generate a minimal main for the server
            Put_Line (File, "with AWS.Config.Set;");
            Put_Line (File, "with AWS.Server;");
            Put_Line (File, "with AWS.Status;");
            Put_Line (File, "with AWS.Response;");
            Put_Line (File, "with SOAP.Dispatchers.Callback;");
            New_Line (File);
            Put_Line (File, "with " & U_Name & ".CB;");
            Put_Line (File, "with " & U_Name& ".Server;");
            New_Line (File);
            Put_Line (File, "procedure " & To_Unit_Name (Filename) & " is");
            New_Line (File);
            Put_Line (File, "   use AWS;");
            New_Line (File);
            Put_Line (File, "   function CB ");
            Put_Line (File, "      (Request : in Status.Data)");
            Put_Line (File, "       return Response.Data");
            Put_Line (File, "   is");
            Put_Line (File, "      R : Response.Data;");
            Put_Line (File, "   begin");
            Put_Line (File, "      return R;");
            Put_Line (File, "   end CB;");
            New_Line (File);
            Put_Line (File, "   WS   : AWS.Server.HTTP;");
            Put_Line (File, "   Conf : Config.Object;");
            Put_Line (File, "   Disp : " & U_Name & ".CB.Handler;");
            New_Line (File);
            Put_Line (File, "begin");
            Put_Line (File, "   Config.Set.Server_Port");
            Put_Line (File, "      (Conf, " & U_Name & ".Server.Port);");
            Put_Line (File, "   Disp := SOAP.Dispatchers.Callback.Create");
            Put_Line (File, "     (CB'Unrestricted_Access,");
            Put_Line (File, "      " & U_Name & ".CB.SOAP_CB'Access);");
            New_Line (File);
            Put_Line (File, "   AWS.Server.Start (WS, Disp, Conf);");
            New_Line (File);
            Put_Line (File, "   AWS.Server.Wait (AWS.Server.Forever);");
            Put_Line (File, "end " & To_Unit_Name (Filename) & ";");
         end if;

         Text_IO.Close (File);
      end Generate_Main;

      LL_Name : constant String
        := Characters.Handling.To_Lower (Format_Name (O, Name));

   begin
      O.Location := To_Unbounded_String (Location);

      if not O.Quiet then
         Text_IO.New_Line;
         Text_IO.Put_Line ("Service " & Name);
         Text_IO.Put_Line ("   " & Documentation);
      end if;

      Create (Root, LL_Name & ".ads");

      Create (Type_Ads, LL_Name & "-types.ads");
      Create (Type_Adb, LL_Name & "-types.adb");

      if O.Gen_Stub then
         Create (Stub_Ads, LL_Name & "-client.ads");
         Create (Stub_Adb, LL_Name & "-client.adb");
      end if;

      if O.Gen_Skel then
         Create (Skel_Ads, LL_Name & "-server.ads");
         Create (Skel_Adb, LL_Name & "-server.adb");
      end if;

      if O.Gen_CB then
         Create (CB_Ads, LL_Name & "-cb.ads");
         Create (CB_Adb, LL_Name & "-cb.adb");
         Text_IO.Create (Tmp_Adb, Text_IO.Out_File);
      end if;

      --  Types

      Put_File_Header (O, Type_Ads);

      Text_IO.Put_Line (Type_Ads, "with Ada.Calendar;");
      Text_IO.Put_Line (Type_Ads, "with Ada.Strings.Unbounded;");
      Text_IO.New_Line (Type_Ads);
      Text_IO.Put_Line (Type_Ads, "with SOAP.Types;");
      Text_IO.Put_Line (Type_Ads, "with SOAP.Utils;");
      Text_IO.New_Line (Type_Ads);

      if O.Types_Spec /= Null_Unbounded_String then
         Text_IO.Put_Line (Type_Ads, "with " & To_String (O.Types_Spec) & ';');
         Text_IO.New_Line (Type_Ads);
      end if;

      Text_IO.Put_Line
        (Type_Ads, "package " & U_Name & ".Types is");
      Text_IO.New_Line (Type_Ads);
      Text_IO.Put_Line (Type_Ads, "   pragma Warnings (Off, Ada.Calendar);");
      Text_IO.Put_Line
        (Type_Ads, "   pragma Warnings (Off, Ada.Strings.Unbounded);");
      Text_IO.Put_Line (Type_Ads, "   pragma Warnings (Off, SOAP.Types);");
      Text_IO.Put_Line (Type_Ads, "   pragma Warnings (Off, SOAP.Utils);");

      if O.Types_Spec /= Null_Unbounded_String then
         Text_IO.Put_Line
           (Type_Ads,
            "   pragma Warnings (Off, " & To_String (O.Types_Spec) & ");");
         Text_IO.New_Line (Type_Ads);
      end if;

      Text_IO.New_Line (Type_Ads);
      Text_IO.Put_Line (Type_Ads, "   pragma Style_Checks (Off);");
      Text_IO.New_Line (Type_Ads);
      Text_IO.Put_Line (Type_Ads, "   pragma Elaborate_Body;");
      Text_IO.New_Line (Type_Ads);
      Text_IO.Put_Line (Type_Ads, "   use Ada.Strings.Unbounded;");
      Text_IO.New_Line (Type_Ads);
      Text_IO.Put_Line (Type_Ads, "    function ""+""");
      Text_IO.Put_Line (Type_Ads, "      (Str : in String)");
      Text_IO.Put_Line (Type_Ads, "       return Unbounded_String");
      Text_IO.Put_Line (Type_Ads, "       renames To_Unbounded_String;");


      Put_File_Header (O, Type_Adb);

      Text_IO.Put_Line
        (Type_Adb, "package body " & U_Name & ".Types is");
      Text_IO.New_Line (Type_Adb);
      Text_IO.Put_Line (Type_Adb, "   use SOAP.Types;");

      --  Root

      Put_File_Header (O, Root);

      if Documentation /= "" then
         Text_IO.Put_Line (Root, "--  " & Documentation);
         Text_IO.New_Line (Root);
      end if;

      Text_IO.Put_Line (Root, "package " & U_Name & " is");

      Text_IO.New_Line (Root);
      Text_IO.Put_Line (Root,
                        "   URL : constant String := """ & Location & """;");

      if O.WSDL_File /= Null_Unbounded_String then
         Text_IO.New_Line (Root);
         Text_IO.Put_Line (Root, "   pragma Style_Checks (Off);");

         declare
            File   : Text_IO.File_Type;
            Buffer : String (1 .. 1_024);
            Last   : Natural;
         begin
            Text_IO.Open (File, Text_IO.In_File, To_String (O.WSDL_File));

            while not Text_IO.End_Of_File (File) loop
               Text_IO.Get_Line (File, Buffer, Last);
               Text_IO.Put_Line (Root, "--  " & Buffer (1 .. Last));
            end loop;

            Text_IO.Close (File);
         end;

         Text_IO.Put_Line (Root, "   pragma Style_Checks (On);");
         Text_IO.New_Line (Root);
      end if;

      O.Unit := To_Unbounded_String (U_Name);

      --  Stubs

      if O.Gen_Stub then
         Put_File_Header (O, Stub_Ads);
         Put_File_Header (O, Stub_Adb);
         Stub.Start_Service (O, Name, Documentation, Location);
      end if;

      --  Skeletons

      if O.Gen_Skel then
         Put_File_Header (O, Skel_Ads);
         Put_File_Header (O, Skel_Adb);
         Skel.Start_Service (O, Name, Documentation, Location);
      end if;

      --  Callbacks

      if O.Gen_CB then
         Put_File_Header (O, CB_Ads);
         Put_File_Header (O, CB_Adb);
         CB.Start_Service (O, Name, Documentation, Location);
      end if;

      --  Main

      if O.Main /= Null_Unbounded_String then
         Generate_Main (To_String (O.Main));
      end if;
   end Start_Service;

   ----------
   -- Stub --
   ----------

   package body Stub is separate;

   ----------------
   -- Time_Stamp --
   ----------------

   function Time_Stamp return String is
   begin
      return "--  This file was generated on "
        & GNAT.Calendar.Time_IO.Image
            (Ada.Calendar.Clock, "%A %d %B %Y at %T");
   end Time_Stamp;

   ------------------
   -- To_Unit_Name --
   ------------------

   function To_Unit_Name (Filename : in String) return String is
   begin
      return Strings.Fixed.Translate
        (Filename, Strings.Maps.To_Mapping ("-", "."));
   end To_Unit_Name;

   ----------------
   -- Types_From --
   ----------------

   procedure Types_From (O : in out Object; Spec : in String) is
   begin
      O.Types_Spec := To_Unbounded_String (To_Unit_Name (Spec));
   end Types_From;

   --------------------
   -- Version_String --
   --------------------

   function Version_String return String is
   begin
      return "--  AWS " & AWS.Version
        & " - SOAP " & SOAP.Version;
   end Version_String;

   ---------------
   -- WSDL_File --
   ---------------

   procedure WSDL_File (O : in out Object; Filename : in String) is
   begin
      O.WSDL_File := To_Unbounded_String (Filename);
   end WSDL_File;

end SOAP.Generator;
