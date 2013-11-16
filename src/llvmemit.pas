unit llvmemit;
{$ifdef FPC}
{$mode delphi}{$H+}
{$endif}

interface
uses Classes, SysUtils, ast, cntx, ptrhashtable;

{$define CHECKTYPE}

type
  TExprState = (esNone, esAddrOfMember);
  TCGState = (gsInTop, gsInFunc);
  TCGStates = set of TCGState;

  // ��Ҫ�õ���LLVMָ���
  TLLVMIntrinsic = (
    llvm_memcpy, llvm_memmove, llvm_rint,
    llvm_ovfi8, llvm_ovfi16, llvm_ovfi32, llvm_ovfi64
  );
  TLLVMIntrinsics = set of TLLVMIntrinsic;

  TSysRoutine = (
    sys_ovf_check, sys_range_check, sys_io_check,
    sys_astr, sys_wstr, sys_ustr, sys_sstr,
    sys_var, sys_conv, sys_math, 
    sys_raise
  );
  TSysRoutines = set of TSysRoutine;

  TBaseType = (btErr, btInt, btFlt, btCur, btBol, btChr, btStr, btSet, btVar, btPtr);

  TAutoInitVarType = (
      aivtAStr, aivtWStr, aivtUStr, aivtSStr,
      aivtDynArray, aivtIntf, aivtVariant
  );

  TLLVMType = (ltI1, ltI8, ltI16, ltI32, ltI64, ltF32, ltF64, ltStruct, ltPtr);

{  TLoadConstState = (lcsCurrency, lcsString);
  TLoadConstStates = set of TLoadConstState;}

  TVarState = (vasAddrOfVar, vasCurrConst, vasAddrValue);
  TVarStates = set of TVarState;

  TVarInfo = record
    Name, TyStr: string;
    States: TVarStates;
//    Ty: TLLVMType;
  end;

  TTempVarInfo = class
  public
    Name: string;
  //  TyStr: string;
  //  Index, ArrayIndex: Word;
    Typ: TAutoInitVarType;
  end;

  TWStrInitInfo = class
  public
    VarName: string;
    DataVarName: string;
    DataTyStr: string;
  end;

  TEmitFuncContext = class
  private
    procedure ClearTempVars;
  public
    Func: TFunction;
    ResultVar, SelfVar: TVariable;
    MangledName: string;
    FrameDecl: string;     // frame������
    FrameTyStr: string;    // frame��������
    FrameAlign: Byte;
    Level: Byte;           // Func.Level
    LinkedFrameIndex: Word; // ������һ���������
    NeedFrame: Boolean;    // ��ǰ�����ı����������Ƕ�׺������ã���ҪFrame�ṹ
    HasNest: Boolean;
    RetConverted: Boolean;       // ����ֵת��Ϊ����
    IsSafecall: Boolean;
    IsMeth, IsCtor, IsDtor: Boolean;

    TempID, LabelID: Integer;
    TempInitVars: TList;   // ��Ҫ��ʼ/�ͷŵ������е���ʱ����
    ExitLabel: string;

    destructor Destroy; override;
    procedure AddTempVar(const Name: string; vt: TAutoInitVarType);
  end;

  TCPUKind = (ckX86, ckX86_64, ckARM, ckXCore, ckPPC32, ckPPC64);
  TCPUWordSize = (cws32, cws64);

  TAddSubMulOp = opADD..opMUL;
  TLLVMIntType = ltI8..ltI64;

  //TSysTypeInfo = (stiString, stiWideString, sti);

  ECodeGenError = class(Exception);

  TCodeGen = class
  private
    FContext: TCompileContext;
    FModule: TModule;
    FCodes: TStringList;
    FDecls: TStringList;
    FExternalDecls: TPtrHashTable; // �ⲿ����
    FEmittedSymbols: TPtrHashTable; // �Ѿ��������ⲿ����
    FWStrInitList: TList;
    FLandingpads: TStringList;
    FCurCntx: TEmitFuncContext;
    FIntrinsics: TLLVMIntrinsics;
    FSysRoutines: set of TSystemRoutine;

//    FCurLandingPad: string;
    FBreakLabel, FContinueLabel: string;
    FCntxList: TList;

    FNewInstanceFunc,
    FAfterConstructionFunc,
    FFreeInstanceFunc,
    FBeforeDestructionFunc: TMethod;

    function WriteCode(const S: string): Integer; overload;
    function WriteCode(const S: string; const Args: array of const): Integer; overload;
    function WriteLabel(const S: string): Integer;
    procedure WriteDecl(const S: string); overload;
    procedure WriteDecl(const S: string; const Args: array of const); overload;
    procedure EmitIns_Memcpy(const desT, desN, srcT, srcN: string; len: Int64; vol: Boolean = False);

    // ������ʵ������VMTָ����λ��Offset�ĺ���ָ��
    // VmtVar����ʵ����������,
    procedure EmitLoadVmt(const VmtVar, VmtTy: string; IsInst: Boolean;
      Offset: Integer; out FunPtr: string);
    procedure EmitLoadVmtCast(const VmtVar, VmtTy: string; IsInst: Boolean;
      CastFunc: TMethod; out FunPtr, FunTy: string);
    procedure EmitFunc(Func: TFunctionDecl);
    procedure EmitStmt(Stmt: TStatement);
    procedure EmitExpr(const E: TExpr; out Result: TVarInfo);
    procedure EmitOp_LoadRef(Ref: TSymbol; out Result: TVarInfo);
    procedure EmitOp_Load(E: TSymbolExpr; out Result: TVarInfo);
    procedure EmitOp_LoadConst(E: TConstExpr; out Result: TVarInfo);
    procedure EmitOp_LoadConstValue(const Value: TValueRec; T: TType; out Result: TVarInfo);
    procedure EmitOp_Addr(E: TUnaryExpr; out Result: TVarInfo);
    procedure EmitOp_Inst(E: TUnaryExpr; out Result: TVarInfo);
    procedure EmitOp_Not(E: TUnaryExpr; out Result: TVarInfo);
    procedure EmitOp_Neg(E: TUnaryExpr; out Result: TVarInfo);
    procedure EmitOp_Cast(E: TBinaryExpr; out Result: TVarInfo);
    procedure EmitOp_Index(E: TBinaryExpr; out Result: TVarInfo);
    procedure EmitOp_Member(E: TBinaryExpr; out Result: TVarInfo);
    procedure EmitSymbolDecl(Sym: TSymbol);
    procedure EmitTypeDecl(T: TType);
    procedure EmitGlobalVarDecl(V: TVariable);
    procedure EmitAStr(pub: Boolean; const name, s: string);
    procedure EmitWStr(pub: Boolean; const name: string; const s: WideString);
    procedure EmitUStr(pub: Boolean; const name: string; const s: WideString);

    {function EmitCall(const cc, invStmt, fn_attr: string): string; overload;}
    procedure EmitCall(const func, retVar, cc, fn_attr: string;
                       const typs, args: array of string); overload;

    procedure EmitCall(Func: TFunctionDecl;
                      const Typs, Args: array of string;
                      const RetVar: string); overload;

    function TempVar: string;
    function LabelStr: string;
    function CurLandingPad: string;

    procedure AddInitWStr(const VarName, DataVarName, DataTyStr: string); 
    procedure ClearWStrInitList;

    function TypeStr(Typ: TType): string;
    function ArgTypeStr(T: TType; Modifier: TArgumentModifier): string;
    function ArgDeclStr(Arg: TArgument; NeedName: Boolean): string;
    // ���Name='', ֻ�����������,�����������ΪName�ı���
    function ProcTypeStr(T: TProceduralType; const Name: string = ''): string;

    // ���Name='',��ʹ��MangledName(F.Name)��Ϊ����
    function FuncDecl(F: TFunctionDecl; NeedArgName: Boolean;
                      const Name: string = ''): string;
    function CCStr(cc: TCallingConvention): string;

    // �����ⲿ����(����,RTTI,���͵�)
    procedure EmitExternalDecl;
    // ����ϵͳ���͵�RTTI
    procedure EmitSysTypeInfo;

    procedure EmitError(const Msg: string); overload;
    procedure EmitError(const Msg: string; const Args: array of const); overload;
    procedure EmitError(const Coord: TAstNodeCoord; const Msg: string); overload;
    procedure EmitError(const Coord: TAstNodeCoord; const Msg: string; const Args: array of const); overload;

  protected
    // ������RTTI��Ϣ
    procedure EmitRtti_Class(T: TClassType);
    procedure EmitRtti_Record(T: TRecordType);
    procedure EmitRtti_Object(T: TObjectType);
    procedure EmitRtti_Intf(T: TInterfaceType);
    procedure EmitRtti_Class_External(T: TClassType);
    procedure EmitRtti_Record_External(T: TRecordType);
    procedure EmitRtti_Object_External(T: TObjectType);
    procedure EmitRtti_Intf_External(T: TInterfaceType);

    // ������Ԫ����
    procedure EmitExternals;
    // LLVMָ�������
    procedure EmitIntrinsics;
    // ��System��Ԫ��ϵͳ�������е���
    procedure EmitCallSys(Routine: TSystemRoutine;
                          const Typs, Args: array of string;
                          const RetVar: string = '');

    procedure EmitIns_IntTrunc(var Result: TVarInfo; const desT: string);
    procedure EmitIns_FltTrunc(var Result: TVarInfo; const desT: string);
    procedure EmitIns_IntExt(var Result: TVarInfo; const desT: string; sign: Boolean);
    procedure EmitIns_FltExt(var Result: TVarInfo; const desT: string);
    procedure EmitIns_Int2Flt(var Result: TVarInfo; const desT: string; sign: Boolean);
    procedure EmitIns_Int2Cur(var Result: TVarInfo; sign: Boolean);
    procedure EmitIns_Int2Bol(var Result: TVarInfo);
    procedure EmitIns_Bol2Bol(var Result: TVarInfo; typ: TTypeCode);
    procedure EmitIns_Bol2I1(var Result: TVarInfo);
    procedure EmitIns_Bit2Bol(var Result: TVarInfo);
    procedure EmitIns_Flt2Cur(var Result: TVarInfo);
    procedure EmitIns_Cur2Flt(var Result: TVarInfo; const desT: string);
    procedure EmitIns_Cur2Comp(var Result: TVarInfo);
    procedure EmitIns_Ptr2Int(var Result: TVarInfo; const desT: string);
    procedure EmitIns_Int2Ptr(var Result: TVarInfo; const desT: string);
    procedure EmitBuiltin(E: TBinaryExpr; Func: TBuiltinFunction; Args: TUnaryExpr; out Result: TVarInfo);
    procedure EmitAssign(LT: TType; Switches: TCodeSwitches; Right: TExpr; var LV, RV: TVarInfo);
    procedure EmitOp_Call(E: TBinaryExpr; var Result: TVarInfo);
    procedure EmitOp_VarLoad(var Result: TVarInfo); overload;
    procedure EmitOp_VarLoad(const Src: TVarInfo; out Des: TVarInfo); overload;
    procedure EmitOp_Ptr(E: TExpr; var Result: TVarInfo);
    procedure EmitOp_Int(E: TExpr; var Result: TVarInfo);
    procedure EmitOp_Int64(E: TExpr; var Result: TVarInfo);
    procedure EmitOp_Float(E: TExpr; var Result: TVarInfo);
    procedure EmitOp_Currency(E: TExpr; var Result: TVarInfo);
    procedure EmitOp_IntOvf(var L, R, Result: TVarInfo; Op: TAddSubMulOp; Ty: TLLVMIntType; IsSign: Boolean);
    procedure EmitOp_Boolean(E: TExpr; out Result: TVarInfo);

    procedure EmitFuncCall(E: TBinaryExpr; Fun: TFunctionDecl;
        FunT: TProceduralType; var Result: TVarInfo);
    procedure EmitCast(var R: TVarInfo; RT, LT: TType);
    procedure EmitRangeCheck(var V: TVarInfo; RT, LT: TType);
    function IsRangeCheckNeeded(RT, LT: TType): Boolean;
    procedure EmitStmt_Assign(Stmt: TAssignmentStmt);
    procedure EmitStmt_If(Stmt: TIfStmt);
    procedure EmitStmt_For(Stmt: TForStmt);
    procedure EmitStmt_While(Stmt: TWhileStmt);
    procedure EmitStmt_Repeat(Stmt: TRepeatStmt);
    procedure EmitStmt_Try(Stmt: TTryStmt);
    procedure EmitStmt_Call(Stmt: TCallStmt);

//    procedure EmitBuiltinFunc(E: TBinaryExpr);
  public
    CPU: TCPUKind;
    CPUWordSize: TCPUWordSize;   // CPU�ֳ�
    DefCC: string;    // ȱʡ�ĵ���Լ��
    NativeIntStr: string;  // ȱʡInt: i32 i64

    constructor Create;
    destructor Destroy; override;
    procedure EmitModule(M: TModule; Cntx: TCompileContext);

    property Codes: TStringList read FCodes;
    function GetIR: string;
  end;

implementation

const
  SpecialTypes = [typAnsiString, typWideString, typUnicodeString,
    typShortString, typVariant, typOleVariant, typRecord, typObject,
    typArray, typDynamicArray];
  StructTypes = [typShortString, typVariant, typOleVariant,
    typRecord, typObject, typArray, typSet, typOpenArray]; // set���С��4�ֽڲ����ɽṹ����

  Visibility: array[Boolean] of string = ('private', '');

  llvmTypeNames: array[ltI1..ltF64] of string = (
    'i1', 'i8', 'i16', 'i32', 'i64', 'float', 'double'
  );

const
  // typShortint..typUnicodeString����ֱ��ȡtypMaps
  typMaps: array[typUntype..typDynamicArray] of string = (
//    typUntype
    'i8',
//    typShortint, typByte, typSmallint, typWord, typLongint, typLongWord, typInt64, typUInt64,
    'i8', 'i8', 'i16', 'i16', 'i32', 'i32', 'i64', 'i64',
//    typComp, typReal48, typSingle, typDouble, typExtended, typCurrency,
    'i64', 'double', 'float', 'double', 'double', 'i64',
//    typBoolean, typByteBool, typWordBool, typLongBool,
    'i8', 'i8', 'i16', 'i32',
//    typAnsiChar, typWideChar,
    'i8', 'i16',
//    typPointer, typPAnsiChar, typPWideChar,
    'i8*', 'i8*', 'i16*',
//    typAnsiString, typWideString, typUnicodeString, typShortString,
    'i8*', 'i16*', 'i16*', 'i8*',
//    typVariant, typOleVariant,
    '%System.TVarData', '%System.TVarData',
//    typFile, typText,
    'i8*', 'i8*',  // untyped ptr
//    typProcedural,
    'i8*',
//    typRecord, typObject, typClass, typInterface, typDispInterface, typClassRef,
    'i8*', 'i8*', 'i8*', 'i8**', 'i8**', 'i8*',
//    typEnum, typSet, typSubrange, typArray, typDynamicArray,
    'i8', 'i8', 'i8', 'i8*', 'i8*'
  );

type
  TBaseKind = (
    bkErr, bkBol, bkInt, bkBig, bkFlt, bkCur, bkChr, bkStr, bkVar, bkPtr, bkAny
  );
const
  SimpleOpMaps: array[bkBol..bkAny, bkBol..bkAny] of TBaseKind = (
  //     bkBol, bkInt, bkBig, bkFlt, bkCur, bkChr, bkStr, bkVar, bkPtr, bkAny
//---------------------------------------------------------------------
{bkBol} (bkBol, bkErr, bkErr, bkErr, bkErr, bkErr, bkErr, bkVar, bkErr, bkAny),
{bkInt} (bkErr, bkInt, bkBig, bkFlt, bkCur, bkErr, bkErr, bkVar, bkPtr, bkAny),
{bkBig} (bkErr, bkBig, bkBig, bkFlt, bkCur, bkErr, bkErr, bkVar, bkPtr, bkAny),
{bkFlt} (bkErr, bkFlt, bkFlt, bkFlt, bkCur, bkErr, bkErr, bkVar, bkErr, bkAny),
{bkCur} (bkErr, bkCur, bkCur, bkCur, bkCur, bkErr, bkErr, bkVar, bkErr, bkAny),
{bkChr} (bkErr, bkErr, bkErr, bkErr, bkErr, bkStr, bkStr, bkVar, bkErr, bkAny),
{bkStr} (bkErr, bkErr, bkErr, bkErr, bkErr, bkStr, bkStr, bkVar, bkErr, bkAny),
{bkVar} (bkVar, bkVar, bkVar, bkVar, bkVar, bkVar, bkVar, bkVar, bkErr, bkAny),
{bkPtr} (bkErr, bkPtr, bkPtr, bkErr, bkErr, bkErr, bkErr, bkErr, bkPtr, bkAny),
{bkAny} (bkAny, bkAny, bkAny, bkAny, bkAny, bkAny, bkAny, bkAny, bkAny, bkAny)
  );

  BaseMaps: array[TTypeCode] of TBaseKind = (
  //  typUnknown, typUntype,
    bkAny, bkAny,
  //  typShortint, typByte, typSmallint, typWord, typLongint, typLongWord, typInt64, typUInt64,
    bkInt, bkInt, bkInt, bkInt, bkInt, bkInt, bkBig, bkBig,
  //  typComp, typReal48, typSingle, typDouble, typExtended, typCurrency,
    bkFlt, bkFlt, bkFlt, bkFlt, bkFlt, bkCur,
  //  typBoolean, typByteBool, typWordBool, typLongBool,
    bkBol, bkBol, bkBol, bkBol,
  //  typAnsiChar, typWideChar,
    bkChr, bkChr,
  //  typPointer, typPAnsiChar, typPWideChar,
    bkAny, bkAny, bkAny,
  //  typAnsiString, typWideString, typUnicodeString, typShortString,
    bkStr, bkStr, bkStr, bkStr,
  //  typVariant, typOleVariant,
    bkVar, bkVar,
  //  typFile, typText,
    bkAny, bkAny,
  //  typProcedural,
    bkAny,
  //  typRecord, typObject, typClass, typInterface, typDispInterface, typClassRef,
    bkAny, bkAny, bkAny, bkAny, bkAny, bkAny,
  //  typEnum, typSet, typSubrange, typArray, typDynamicArray,
    bkAny, bkAny, bkAny, bkAny, bkAny,
  //  typSymbol,
    bkAny,
  //  typAlias, typClonedType, typOpenArray
    bkAny, bkAny, bkAny
  );
  
const
  BoolStr: array[Boolean] of string = ('false', 'true');
  IntBoolStr: array[Boolean] of string = ('0', '1');

                         // Signed.
  ICmpOpMaps: array[opNE..opGE, Boolean] of string = (
        // False,        True
  {opNE} ('icmp ne',  'icmp ne'),
  {opEQ} ('icmp eq',  'icmp eq'),
  {opLT} ('icmp ult', 'icmp slt'),
  {opLE} ('icmp ule', 'icmp sle'),
  {opGT} ('icmp ugt', 'icmp sgt'),
  {opGE} ('icmp uge', 'icmp sge')
  );

  ArithOpMaps: array[opADD..opSHR] of string = (
//    opADD, opSUB, opOR, opXOR,
    'add', 'sub', 'or', 'xor',
//    opMUL, opFDIV, opIDIV, opMOD, opAND, opSHL, opSHR,
    'mul', 'fdiv', 'div', 'urem', 'and', 'shl', 'lshr'
  );

(*
ShortString     [size x i8]
AnsiString      i8*
WideString      i16*
UnicodeString   i16*
Record          <size x i8>
Object          <size x i8>
Class           <size x i8>
ClassRef        i8*
Interface       i8**
Set             i8, i16, i32, <byte x i8>
*)

// �Ƿ�ṹ������.
// �������͵Ĳ���һ�㴫��ָ��
function IsStructType(T: TType): Boolean;
begin
  T := T.OriginalType;
  if T.TypeCode = typSet then
    Result := T.Size > 4
  else if T.TypeCode = typProcedural then
    Result := TProceduralType(T).IsMethodPointer
  else
    Result := T.TypeCode in StructTypes;
end;

// �Ƿ���������.
// �������͵�����ֵ,����ֱ�ӷ���,��Ҫ�ɵ��÷��ṩ���յ�ַ
function IsSpecialType(T: TType): Boolean;
begin
  T := T.OriginalType;
  if T.TypeCode = typSet then
    Result := T.Size > 4
  else if T.TypeCode = typProcedural then
    Result := TProceduralType(T).IsMethodPointer
  else
    Result := T.TypeCode in SpecialTypes;
end;

function NeedInit(T: TType): Boolean;
begin
  case T.TypeCode of
    typArray: Result := staNeedInit in TArrayType(T).ArrayAttr;
    typRecord: Result := staNeedInit in TRecordType(T).RecordAttr;
  else
    Result := T.TypeCode in AutoInitTypes;
  end;
end;

function NeedFree(T: TType): Boolean;
begin
  case T.TypeCode of
    typArray: Result := staNeedInit in TArrayType(T).ArrayAttr;
    typRecord: Result := staNeedInit in TRecordType(T).RecordAttr;
  else
    Result := T.TypeCode in AutoFreeTypes;
  end;
end;

function InitTabVar(T: TType): string;
begin
  Result := Format('%s.$init', [T.Name]);
end;

function InitTabType(T: TType): string;
begin
  Result := Format('%s.$.init', [T.Name]);
end;

function MangledName(Sym: TSymbol): string;
begin
  Result := '';
  while Sym <> nil do
  begin
    if Result <> '' then
      Result := '.' + Result;
    if (Sym.NodeKind in [nkFunc, nkMethod, nkExternalFunc])
        and TFunctionDecl(Sym).IsOverload then
      Result := Sym.Name + '$' + IntToStr(TFunctionDecl(Sym).ID)
    else
      Result := Sym.Name + Result;
    Sym := Sym.Parent;
  end;
end;

function LastChar(const s: string): Char;
begin
  if s <> '' then
    Result := s[Length(s)]
  else
    Result := #0;
end;

procedure RemoveLastChar(var s: string); overload;
begin
  if s <> '' then
    Delete(s, Length(s), 1);
end;

procedure RemoveLastChar(var s: string; count: Integer); overload;
begin
  if s <> '' then
    Delete(s, Length(s) - count + 1, count);
end;

function EncodeWStr(const s: WideString): AnsiString;
var
  I: Integer;
  C: WideChar;
begin
  Result := '';
  for I := 1 to Length(s) do
  begin
    C := s[I];
    Result := Result + 'i16 ' + IntToStr(Word(C)) + ',';
  end;
  Result := Result + 'i16 0';
end;

function EncodeAStr(const s: AnsiString; TailNullChar: Boolean = True): AnsiString;
var
  I: Integer;
  C: AnsiChar;
begin
  Result := s;
  for I := Length(Result) downto 1 do
  begin
    C := Result[I];
    if (C < #32) or (C > #126) then
    begin
      Result[I] := '\';
      Insert(Format('%.2x', [Ord(C)]), Result, I + 1);
    end;
  end;
  if TailNullChar then Result := Result + '\00';
end;

var
  llvmIntTypeStrs: array[0..5] of string = (
    'i1', 'i8', 'i16', 'i32', 'i64', 'i128'
  );

  llvmFloatTypeStrs: array[0..1] of string = (
    'float', 'double'
  );

// ȷ��TypStr��typeList��
procedure EnsureType(const TypStr: string; typeList: array of string;
  const msg: string); overload;
var
  i: Integer;
begin
  for i := 0 to Length(typeList) - 1 do
    if TypStr = typeList[i] then Exit;

  raise ECodeGenError.Create(msg);
end;

procedure EnsureType(const TyStr1, TyStr2: string; const msg: string); overload;
begin
  if TyStr1 <> TyStr2 then
    raise ECodeGenError.Create(msg);
end;

// ȷ��desT����һ��ָ��
procedure EnsurePtr(const desT, msg: string);
begin
  if LastChar(desT) <> '*' then
    raise ECodeGenError.Create(msg);
end;

function DecodeTyStr(const S: string): TLLVMIntType;
begin
  if S = 'i8' then
    Result := ltI8
  else if S = 'i16' then
    Result := ltI16
  else if S = 'i32' then
    Result := ltI32
  else if S = 'i64' then
    Result := ltI64
  else
    Result := ltI32;
end;

function CountOf(E: TExpr): Integer;
begin
  Result := 0;
  while E <> nil do
  begin
    Inc(Result);
    E := TExpr(E.Next);
  end;
end;

procedure VarInfoCopy(const Src: TVarInfo; out Dest: TVarInfo);
begin
  Dest.Name := Src.Name;
  Dest.TyStr := Src.TyStr;
  Dest.States := Src.States;
end;

procedure VarInfoInit(out V: TVarInfo);
begin
  V.Name := '';
  V.TyStr := '';
  V.States := [];
end;

{ TCodeGen }

procedure TCodeGen.AddInitWStr(const VarName, DataVarName,
  DataTyStr: string);
var
  wsInit: TWStrInitInfo;
begin
  wsInit := TWStrInitInfo.Create;
  wsInit.VarName := VarName;
  wsInit.DataVarName := DataVarName;
  wsInit.DataTyStr := DataTyStr;
  FWStrInitList.Add(wsInit);
end;

function TCodeGen.ArgDeclStr(Arg: TArgument; NeedName: Boolean): string;
var
  T: TType;
  ByRef: Boolean;
begin
  ByRef := False;
  T := Arg.ArgType;
  if T.TypeCode = typUntype then
  begin
    Result := 'i8*';
    ByRef := True;
  end
  else
  begin
    Result := TypeStr(T);

    // ���ڽṹ��������������record,object,array�ȣ�ֻ��ָ��
    if IsStructType(T) or (Arg.Modifier in [argOut, argVar]) then
    begin
      Result := Result + '*';
      ByRef := Arg.Modifier <> argDefault;
    end;
  end;

  if NeedName then
  begin
    Result := Result + ' %' + Arg.Name;
    if ByRef then Result := Result + '.addr';
  end;
end;

function TCodeGen.ArgTypeStr(T: TType; Modifier: TArgumentModifier): string;
begin
  if (T = nil) or (T.TypeCode = typUntype) then
  begin
    Result := 'i8*';
    Exit;
  end;

  Result := TypeStr(T);
  // ���ڽṹ��������������record,object,array�ȣ�ֻ��ָ��
  if IsStructType(T) or (Modifier in [argOut, argVar]) then
    Result := Result + '*';
end;

function TCodeGen.CCStr(cc: TCallingConvention): string;
const
  x86_cc: array [TCallingConvention] of string = (
    // ccDefault, ccRegister, ccPascal, ccCDecl, ccStdCall, ccSafeCall
    'fastcc', 'fastcc', 'ccc', 'ccc', 'cc 64', 'ccc'
  );          // cc 65: x86_FastCall
  other_cc: array [TCallingConvention] of string = (
    // ccDefault, ccRegister, ccPascal, ccCDecl, ccStdCall, ccSafeCall
    'fastcc', 'fastcc', 'ccc', 'ccc', 'ccc', 'ccc'
  );
begin
  if CPU in [ckX86, ckX86_64] then
    Result := x86_cc[cc]
  else
    Result := other_cc[cc];

  DefCC := 'fastcc';
end;

procedure TCodeGen.ClearWStrInitList;
var
  i: Integer;
begin
  for i := 0 to FWStrInitList.Count - 1 do
    TObject(FWStrInitList[i]).Free;
  FWStrInitList.Clear;
end;

constructor TCodeGen.Create;
begin
  FCodes := TStringList.Create;
  FCodes.Capacity := 64;
  FDecls := TStringList.Create;
  FDecls.Capacity := 64;
  FLandingpads := TStringList.Create;
  FExternalDecls := TPtrHashTable.Create;
  FEmittedSymbols := TPtrHashTable.Create;
  FWStrInitList := TList.Create;
  FWStrInitList.Capacity := 16;
  FCntxList := TList.Create;
  FCntxList.Capacity := 16;
  NativeIntStr := 'i32';
end;

function TCodeGen.CurLandingPad: string;
begin
  if FLandingpads.Count > 0 then
    Result := FLandingpads[FLandingpads.Count - 1]
  else
    Result := '';
end;

destructor TCodeGen.Destroy;
begin
  FCodes.Free;
  FDecls.Free;
  FLandingpads.Free;
  FExternalDecls.Free;
  FEmittedSymbols.Free;
  FCntxList.Free;
  ClearWStrInitList;
  FWStrInitList.Free;
  inherited;
end;

procedure TCodeGen.EmitAssign(LT: TType; Switches: TCodeSwitches;
  Right: TExpr; var LV, RV: TVarInfo);
begin
  EmitOp_VarLoad(RV);

  if (cdRangeChecks in Switches) and IsRangeCheckNeeded(Right.Typ, LT) then
  begin
    EmitRangeCheck(RV, Right.Typ, LT);
  end;

  EmitCast(RV, Right.Typ, LT);
  if (Right.Typ.TypeCode = typBoolean) and (RV.TyStr = 'i1') then
    EmitIns_Bit2Bol(RV);

  WriteCode('store %s %s, %s %s', [
    RV.TyStr, RV.Name, LV.TyStr, LV.Name
  ]);
end;

procedure TCodeGen.EmitAStr(pub: Boolean; const name, s: string);
var
  size: Integer;
begin
  size := Length(s) + 1;
  // 0 name, 1 visibility, 2 size, 3 char count, 4 size, 5 string
  WriteDecl(Format('@%s = %s unnamed_addr constant {%%SizeInt, %%SizeInt, [%d x i8]} {%%SizeInt -1, %%SizeInt %d, [%d x i8] c"%s"}',
    [
      name, Visibility[pub], size, size - 1, size, EncodeAStr(s)
    ]));
end;

procedure TCodeGen.EmitBuiltin(E: TBinaryExpr; Func: TBuiltinFunction;
  Args: TUnaryExpr; out Result: TVarInfo);
var
  A1, A2, A3: TExpr;
  V1, V2, V3: TVarInfo;
  Num: Integer;
  Va, Va2, Va3: string;

  procedure EmitBuiltin_Abs;
  begin
    case A1.Typ.TypeCode of
      typShortint, typSmallint, typLongint,
      typInt64, typComp, typCurrency:
        begin
          {
            %cmp = icmp slt i32 %a, 0
            %sub = sub nsw i32 0, %a
            %cond = select i1 %cmp, i32 %sub, i32 %a
          }
          Va := TempVar;
          WriteCode('%s = icmp slt %s %s, 0', [
            Va, V1.TyStr, V1.Name]);
          Va2 := TempVar;
          WriteCode('%s = sub i32 0, %s', [Va2, V1.Name]);
          Va3 := TempVar;
          // 0: result, 1: comp result, 2,3: sub result, 4,5:source 
          WriteCode('%s = select i1 %s, %s %s, %s %s', [
            Va3, Va, V1.TyStr, Va2, V1.TyStr, V1.Name]);
          Result.Name := Va3;
          Result.TyStr := V1.TyStr;
          Result.States := [];
        end;
      typByte, typWord, typLongWord, typUInt64:
        begin
          Result.Name := V1.Name;
          Result.TyStr := V1.TyStr;
          Result.States := V1.States;
        end;
      typSingle:
        begin
          Va := TempVar;
          WriteCode('%s = call @llvm.fabs.f32(float %s)', [Va, V1.Name]);
          Result.Name := Va;
          Result.TyStr := V1.TyStr;
          Result.States := [];
        end;
      typReal48, typDouble, typExtended:
        begin
          Va := TempVar;
          WriteCode('%s = call @llvm.fabs.f64(double %s)', [Va, V1.Name]);
          Result.Name := Va;
          Result.TyStr := V1.TyStr;
          Result.States := [];
        end;
    else
      Assert(False);
    end;
  end;

  procedure EmitBuiltin_Addr;
  begin
    Result.Name := V1.Name;
    Result.TyStr := V1.TyStr;
    Result.States := V1.States;
    if vasAddrOfVar in Result.States then
    begin
      Exclude(Result.States, vasAddrOfVar);
      Include(Result.States, vasAddrValue);
    end
    else
      EmitError(E.Coord, 'EmitBuiltin_Addr');
  end;

  procedure EmitBuiltin_Assigned;
  begin
    EmitOp_VarLoad(V1);
    // todo 1: Ҫ�����¼�
    Result.Name := TempVar;
    Result.TyStr := 'i1';
    Result.States := [];
    WriteCode('%s = icmp ne %s %s, null', [
      Result.Name, V1.TyStr, V1.Name
      ]);
  end;

  procedure EmitBuiltin_Break;
  begin
    if FBreakLabel = '' then
      EmitError(E.Coord, 'Not break label');
    WriteCode('br label %' + FBreakLabel);
  end;

  procedure EmitBuiltin_Chr;
  begin
    case A1.Typ.TypeCode of
      typShortint..typUInt64:
        begin
          EmitCast(V1, A1.Typ, FContext.FCharType);
          Result.Name := V1.Name;
          Result.TyStr := V1.TyStr;
          Result.States := V1.States;
        end;
    else
      Assert(False);
    end;
  end;

  procedure EmitBuiltin_Ord;
  begin
    EmitOp_VarLoad(V1);
    Result.Name := V1.Name;
    Result.TyStr := V1.TyStr;
    Result.States := V1.States;
  end;

  function IntTy(T: TType): TLLVMIntType;
  begin
    case T.Size of
      1: Result := ltI8;
      2: Result := ltI16;
      4: Result := ltI32;
      8: Result := ltI64;
    else
      Assert(False);
      Result := ltI8;
    end;
  end;

  procedure EmitBuiltin_AddSub(out Result: TVarInfo; DoAdd: Boolean;
    const DeltaVa: string = '1');
  var
    D1: TVarInfo;
  begin
    EmitOp_VarLoad(V1, D1);

    if cdOverflowChecks in E.Switches then
    begin
      V2.Name := DeltaVa;
      V2.TyStr := D1.TyStr;
      V2.States := [];
      //VarInfoInit(Result);
      Result.Name := '';
      // todo 1: ������
      if DoAdd then
        EmitOp_IntOvf(D1, V2, Result, opADD, IntTy(A1.Typ), True)
      else
        EmitOp_IntOvf(D1, V2, Result, opSUB, IntTy(A1.Typ), True)
    end
    else
    begin
      Va := TempVar;
      if DoAdd then
        WriteCode('%s = add %s %s, %s', [Va, D1.TyStr, D1.Name, DeltaVa])
      else
        WriteCode('%s = sub %s %s, %s', [Va, D1.TyStr, D1.Name, DeltaVa]);

      Result.Name := Va;
      Result.TyStr := D1.TyStr;
      Result.States := [];
    end;
    if (cdRangeChecks in E.Switches)
        and (A1.Typ.TypeCode in [typBoolean, typSubrange]) then
      EmitRangeCheck(Result, A1.Typ, A1.Typ);
  end;

  procedure EmitBuiltin_Continue;
  begin
    if FContinueLabel = '' then
      EmitError(E.Coord, 'Not continue label');
    WriteCode('br label %' + FContinueLabel);
  end;

  procedure EmitBuiltin_Copy;
  begin
    Assert(false);
  end;

  procedure EmitBuiltin_IncDecPtr(DoInc: Boolean);
  var
    Va: string;
    D1: TVarInfo;
  begin
    if Num > 1 then
    begin
      EmitOp_VarLoad(V2);
      EmitCast(V2, A2.Typ, FContext.FNativeIntType);
      if not DoInc then
      begin
        Va := TempVar;
        WriteCode('%s = sub %s 0, %s', [
          Va, Self.NativeIntStr, V2.Name
        ]);
        V2.Name := Va;
        V2.TyStr := NativeIntStr;
      end;
    end
    else
    begin
      if DoInc then
        V2.Name := '1'
      else
        V2.Name := '-1';
      V2.TyStr := Self.NativeIntStr;
      V2.States := [];
    end;

    EmitOp_VarLoad(V1, D1);
    Result.Name := TempVar;
    Result.TyStr := D1.TyStr;
    Result.States := [];
    WriteCode('%s = getelementptr %s %s, %s %s', [
      Result.Name, D1.TyStr, D1.Name, V2.TyStr, V2.Name
    ]);
    WriteCode('store %s %s, %s %s', [
      Result.TyStr, Result.Name, V1.TyStr, V1.Name
    ]);
  end;

  procedure EmitBuiltin_IncDec(DoInc: Boolean);
  var
    Ret: TVarInfo;
  begin
    if Num > 1 then
    begin
      EmitOp_VarLoad(V2);
      EmitCast(V2, A2.Typ, A1.Typ);
    end
    else
    begin
      V2.Name := '1';
      V2.TyStr := TypeStr(A1.Typ);
      V2.States := [];
    end;

    {if V2.TyStr <> V1.TyStr then
      EmitError(E.Coord, 'type mismatch');}
    EmitBuiltin_AddSub(Ret, DoInc, V2.Name);
    WriteCode('store %s %s, %s %s', [
      Ret.TyStr, Ret.Name, V1.TyStr, V1.Name
    ]);
  end;

  procedure EmitBuiltin_Exit;
  begin
    if FCurCntx.ExitLabel = '' then
      FCurCntx.ExitLabel := 'quit';
    // todo 1: �˳�֮ǰ��Ҫ��ִ��finally
    
    WriteCode('br label %quit');
  end;
var
  ActualArgs: TUnaryExpr;
  ArgExpr: TExpr;
begin
  Num := 0;
  A1 := nil;
  A2 := nil;
  A3 := nil;
  ActualArgs := TUnaryExpr(E.Right);
  if ActualArgs <> nil then
  begin
    ArgExpr := ActualArgs.Operand;
    while ArgExpr <> nil do
    begin
      case Num of
        0: A1 := ArgExpr;
        1: A2 := ArgExpr;
        2: A3 := ArgExpr;
        else Break;
      end;
      Inc(Num);
      ArgExpr := TExpr(ArgExpr.Next);
    end;
  end;

  if A1 <> nil then
    EmitExpr(A1, V1);
  if A2 <> nil then
    EmitExpr(A2, V2);
  if A3 <> nil then
    EmitExpr(A3, V3);
  case Func.Kind of
{
      bfAbs, bfAddr, bfAssigned, bfBreak, bfChr, bfContinue, bfCopy, bfDec,
      bfDispose, bfExclude, bfExit, bfFinalize, bfFreeMem, bfGetMem,
      bfHi, bfHigh, bfInc, bfInclude, bfInitialize, bfLength, bfLo,
      bfLow, bfNew, bfOdd, bfOrd, bfPred, bfPtr, bfRound, bfSucc, bfSetLength,
      bfSizeOf, bfSwap, bfTrunc, bfTypeInfo
}
    bfAbs: EmitBuiltin_Abs;
    bfAddr: EmitBuiltin_Addr;
    bfAssigned: EmitBuiltin_Assigned;
    bfBreak: EmitBuiltin_Break;
    bfChr: EmitBuiltin_Chr;
    bfContinue: EmitBuiltin_Continue;
    bfCopy: EmitBuiltin_Copy;
    bfDec:
      if A1.Typ.IsPointer then
        EmitBuiltin_IncDecPtr(False)
      else
        EmitBuiltin_IncDec(False);
    bfExit: EmitBuiltin_Exit;
    bfInc:
      if A1.Typ.IsPointer then
        EmitBuiltin_IncDecPtr(True)
      else
        EmitBuiltin_IncDec(True);
    bfOrd: EmitBuiltin_Ord;
    bfPred: EmitBuiltin_AddSub(Result, False);
    bfSucc: EmitBuiltin_AddSub(Result, True);
  else
    Assert(False);
  end;

end;

{function TCodeGen.EmitCall(const cc, invStmt, fn_attr: string): string;
var
  lpad, s, nextLabel: string;
begin
  lpad := Self.CurLandingPad;
  Result := TempVar;
  if lpad = '' then
  begin
    s := Format('%s = tail call %s %s', [Result, InvStmt, fn_attr]);
    WriteCode(s);
  end
  else
  begin
    nextLabel := Self.LabelStr;
    s := Format('%s = invoke %s %s to label %s unwind label %s', [
        Result, cc, invStmt, nextLabel, lpad
      ]);
    WriteCode(s);
    WriteLabel(nextLabel);
  end;
end; }

procedure TCodeGen.EmitCall(Func: TFunctionDecl;
                           const Typs, Args: array of string;
                           const RetVar: string);
var
  argStr, lpad, s, nextLabel: string;
  i: Integer;
begin
  Assert(High(Typs) = High(Args), 'EmitCall, Typs <> Args');
  Assert(Func.CallConvention <> ccSafecall, 'EmitCall, safecall not allow');

  ArgStr := '';
  for i := 0 to High(Typs) do
    argStr := argStr + Format('%s %s, ', [Typs[i], Args[i]]);

  if argStr <> '' then
    Delete(argStr, Length(argStr) - 1, 2);

  if retVar = '' then
    S := ''
  else
    S := RetVar + ' = ';

  lpad := Self.CurLandingPad;
  if lpad = '' then
  begin
    WriteCode('%scall %s %s(%s)', [
      S, CCStr(Func.CallConvention), MangledName(Func), argStr
    ]);
  end
  else
  begin
    nextLabel := Self.LabelStr;
    WriteCode('%sinvoke %s %s(%s) to label %s unwind label %s', [
        S, CCStr(Func.CallConvention), MangledName(Func), argStr, nextLabel, lpad
      ]);
    WriteLabel(nextLabel);
  end;
end;

procedure TCodeGen.EmitCall(const func, retVar, cc, fn_attr: string; const typs,
  args: array of string);
var
  argStr, lpad, s, nextLabel: string;
  i: Integer;
begin
  Assert(High(typs) = High(args), 'EmitCall, typs <> args');

  argStr := '';
  for i := 0 to High(typs) do
  begin
    argStr := argStr + Format('%s %s, ', [typs[i], args[i]]);
  end;

  if argStr <> '' then
    Delete(argStr, Length(argStr) - 1, 2);

  if retVar = '' then
    S := ''
  else
    S := retVar + ' =';
  lpad := Self.CurLandingPad;
  if lpad = '' then
  begin
    WriteCode('%s tail call %s %s(%s)', [
      S, cc, func, argStr
    ]);
  end
  else
  begin
    nextLabel := Self.LabelStr;
    WriteCode('%s invoke %s %s(%s) to label %s unwind label %s', [
        S, cc, func, argStr, nextLabel, lpad
      ]);
    WriteLabel(nextLabel);
  end;
end;

procedure TCodeGen.EmitCallSys(Routine: TSystemRoutine;
    const Typs, Args: array of string;
    const RetVar: string);
begin
  Include(FSysRoutines, Routine);
  EmitCall(FContext.GetSystemRoutine(Routine), Typs, Args, RetVar);
end;

procedure TCodeGen.EmitCast(var R: TVarInfo; RT, LT: TType);

type
  TCastKind = (
    ckNone, ckError,
    ckITrunc, ckSExt, ckZExt,
    ckFpTrunc, ckFpExt,
    ckFp2Si, ckFp2Ui, ckSi2Fp, ckUi2Fp,
    ckCur2Si, {ckCur2Ui, }ckSi2Cur, ckUi2Cur, ckFp2Cur, ckCur2Fp,
    {ckBol2Int, }ckInt2Bol, ckBol2Bol,
    ckPtr2Int, ckInt2Ptr,
    ckPtr2Ptr
  );
const
  CastMaps: array[typShortint..typPWideChar, typShortint..typPWideChar] of TCastKind = (
//            typShortint, typByte,     typSmallint, typWord,     typLongint,  typLongWord, typInt64,   typUInt64,   typComp,     typReal48,   typSingle,   typDouble,   typExtended, typCurrency, typBoolean,  typByteBool, typWordBool, typLongBool, typAnsiChar, typWideChar, typPointer,  typPAnsiChar, typPWideChar
{typShortint} (ckNone,     ckNone,      ckSExt,      ckSExt,      ckSExt,      ckSExt,      ckSExt,     ckSExt,      ckSExt,      ckSi2Fp,     ckSi2Fp,     ckSi2Fp,     ckSi2Fp,     ckSi2Cur,    ckInt2Bol,   ckNone,      ckSExt,      ckSExt,      ckNone,      ckSExt,      ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typByte    } (ckNone,     ckNone,      ckZExt,      ckZExt,      ckZExt,      ckZExt,      ckZExt,     ckZExt,      ckZExt,      ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Cur,    ckInt2Bol,   ckNone,      ckZExt,      ckZExt,      ckNone,      ckZExt,      ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typSmallint} (ckITrunc,   ckITrunc,    ckNone,      ckNone,      ckSExt,      ckSExt,      ckSExt,     ckSExt,      ckSExt,      ckSi2Fp,     ckSi2Fp,     ckSi2Fp,     ckSi2Fp,     ckSi2Cur,    ckInt2Bol,   ckITrunc,    ckNone,      ckSExt,      ckITrunc,    ckNone,      ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typWord    } (ckITrunc,   ckITrunc,    ckNone,      ckNone,      ckZExt,      ckZExt,      ckZExt,     ckZExt,      ckZExt,      ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Cur,    ckInt2Bol,   ckITrunc,    ckNone,      ckZExt,      ckITrunc,    ckNone,      ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typLongint } (ckITrunc,   ckITrunc,    ckITrunc,    ckITrunc,    ckNone,      ckNone,      ckSExt,     ckSExt,      ckSExt,      ckSi2Fp,     ckSi2Fp,     ckSi2Fp,     ckSi2Fp,     ckSi2Cur,    ckInt2Bol,   ckITrunc,    ckITrunc,    ckNone,      ckITrunc,    ckITrunc,    ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typLongWord} (ckITrunc,   ckITrunc,    ckITrunc,    ckITrunc,    ckNone,      ckNone,      ckZExt,     ckZExt,      ckZExt,      ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Cur,    ckInt2Bol,   ckITrunc,    ckITrunc,    ckNone,      ckITrunc,    ckITrunc,    ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typInt64   } (ckITrunc,   ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckNone,     ckNone,      ckNone,      ckSi2Fp,     ckSi2Fp,     ckSi2Fp,     ckSi2Fp,     ckSi2Cur,    ckInt2Bol,   ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typUInt64  } (ckITrunc,   ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckNone,     ckNone,      ckNone,      ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Cur,    ckInt2Bol,   ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typComp    } (ckITrunc,   ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckNone,     ckNone,      ckNone,      ckSi2Fp,     ckSi2Fp,     ckSi2Fp,     ckSi2Fp,     ckSi2Cur,    ckInt2Bol,   ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckITrunc,    ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typReal48  } (ckFp2Si,    ckFp2Ui,     ckFp2Si,     ckFp2Ui,     ckFp2Si,     ckFp2Ui,     ckFp2Si,    ckFp2Ui,     ckFp2Si,     ckNone,      ckFpTrunc,   ckNone,      ckNone,      ckFp2Cur,    ckError,     ckError,     ckError,     ckError,     ckError,     ckError,     ckError,     ckError,      ckError),
{typSingle  } (ckFp2Si,    ckFp2Ui,     ckFp2Si,     ckFp2Ui,     ckFp2Si,     ckFp2Ui,     ckFp2Si,    ckFp2Ui,     ckFp2Si,     ckFpExt,     ckNone,      ckFpExt,     ckFpExt,     ckFp2Cur,    ckError,     ckError,     ckError,     ckError,     ckError,     ckError,     ckError,     ckError,      ckError),
{typDouble  } (ckFp2Si,    ckFp2Ui,     ckFp2Si,     ckFp2Ui,     ckFp2Si,     ckFp2Ui,     ckFp2Si,    ckFp2Ui,     ckFp2Si,     ckNone,      ckFpTrunc,   ckNone,      ckNone,      ckFp2Cur,    ckError,     ckError,     ckError,     ckError,     ckError,     ckError,     ckError,     ckError,      ckError),
{typExtended} (ckFp2Si,    ckFp2Ui,     ckFp2Si,     ckFp2Ui,     ckFp2Si,     ckFp2Ui,     ckFp2Si,    ckFp2Ui,     ckFp2Si,     ckNone,      ckFpTrunc,   ckNone,      ckNone,      ckFp2Cur,    ckError,     ckError,     ckError,     ckError,     ckError,     ckError,     ckError,     ckError,      ckError),
{typCurrency} (ckError,    ckError,     ckError,     ckError,     ckError,     ckError,     ckError,    ckError,     ckCur2Si,    ckCur2Fp,    ckCur2Fp,    ckCur2Fp,    ckCur2Fp,    ckNone,      ckError,     ckError,     ckError,     ckError,     ckError,     ckError,     ckError,     ckError,      ckError),
{typBoolean } (ckNone,     ckNone,      ckZExt,      ckZExt,      ckZExt,      ckZExt,      ckZExt,     ckZExt,      ckZExt,      ckError,     ckError,     ckError,     ckError,     ckError,     ckNone,      ckBol2Bol,   ckBol2Bol,   ckBol2Bol,   ckZExt,      ckZExt,      ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typByteBool} (ckNone,     ckNone,      ckZExt,      ckZExt,      ckZExt,      ckZExt,      ckZExt,     ckZExt,      ckZExt,      ckError,     ckError,     ckError,     ckError,     ckError,     ckInt2Bol,   ckNone,      ckBol2Bol,   ckBol2Bol,   ckNone,      ckZExt,      ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typWordBool} (ckITrunc,   ckITrunc,    ckNone,      ckNone,      ckZExt,      ckZExt,      ckZExt,     ckZExt,      ckZExt,      ckError,     ckError,     ckError,     ckError,     ckError,     ckInt2Bol,   ckBol2Bol,   ckNone,      ckBol2Bol,   ckITrunc,    ckNone,      ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typLongBool} (ckITrunc,   ckITrunc,    ckITrunc,    ckITrunc,    ckNone,      ckNone,      ckZExt,     ckZExt,      ckZExt,      ckError,     ckError,     ckError,     ckError,     ckError,     ckInt2Bol,   ckBol2Bol,   ckBol2Bol,   ckNone,      ckITrunc,    ckITrunc,    ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typAnsiChar} (ckNone,     ckNone,      ckZExt,      ckZExt,      ckZExt,      ckZExt,      ckZExt,     ckZExt,      ckZExt,      ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Cur,    ckInt2Bol,   ckNone,      ckZExt,      ckZExt,      ckNone,      ckZExt,      ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typWideChar} (ckITrunc,   ckITrunc,    ckNone,      ckNone,      ckZExt,      ckZExt,      ckZExt,     ckZExt,      ckZExt,      ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Fp,     ckUi2Cur,    ckInt2Bol,   ckITrunc,    ckNone,      ckZExt,      ckITrunc,    ckNone,      ckInt2Ptr,   ckInt2Ptr,    ckInt2Ptr),
{typPointer } (ckPtr2Int,  ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,  ckPtr2Int,   ckPtr2Int,   ckError,     ckError,     ckError,     ckError,     ckError,     ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Ptr,   ckPtr2Ptr,    ckPtr2Ptr),
{typPAnsiChar}(ckPtr2Int,  ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,  ckPtr2Int,   ckPtr2Int,   ckError,     ckError,     ckError,     ckError,     ckError,     ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Ptr,   ckNone,       ckPtr2Ptr),
{typPWideChar}(ckPtr2Int,  ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,  ckPtr2Int,   ckPtr2Int,   ckError,     ckError,     ckError,     ckError,     ckError,     ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Int,   ckPtr2Ptr,   ckPtr2Ptr,    ckNone)
  );

const
          // Signed.
  ExtOp: array[Boolean] of string = ('zext', 'sext');

  procedure EmitBitcast(var V: TVarInfo; const desT: string);
  var
    va: string;
  begin
    if V.TyStr <> desT then
    begin
      EnsurePtr(desT, 'EmitBitcast');
      EnsurePtr(V.TyStr, 'EmitBitcast');
      va := TempVar;
      WriteCode('%s = bitcast %s %s to %s', [va, V.TyStr, V.Name, desT]);
      V.Name := va;
      V.TyStr := desT;
    end;
  end;
var
//  Va: string;
  ck: TCastKind;
begin
  if RT.TypeCode = typSubrange then RT := TSubrangeType(RT).BaseType;
  if LT.TypeCode = typSubrange then LT := TSubrangeType(LT).BaseType;

  if (RT.TypeCode >= typShortint) and (RT.TypeCode <= typPWideChar)
    and (LT.TypeCode >= typShortint) and (LT.TypeCode <= typPWideChar) then
  begin
    ck := CastMaps[RT.TypeCode, LT.TypeCode];
    case ck of
      ckITrunc:
        EmitIns_IntTrunc(R, typMaps[LT.TypeCode]);
      ckSExt:
        EmitIns_IntExt(R, typMaps[LT.TypeCode], True);
      ckZExt:
        EmitIns_IntExt(R, typMaps[LT.TypeCode], False);
      ckFpTrunc:
        EmitIns_FltTrunc(R, typMaps[LT.TypeCode]);
      ckFpExt:
        EmitIns_FltExt(R, typMaps[LT.TypeCode]);
      ckSi2Fp:
        EmitIns_Int2Flt(R, typMaps[LT.TypeCode], True);
      ckUi2Fp:
        EmitIns_Int2Flt(R, typMaps[LT.TypeCode], False);
      ckSi2Cur:
        EmitIns_Int2Cur(R, True);
      ckUi2Cur:
        EmitIns_Int2Cur(R, False);
      ckFp2Cur:
        EmitIns_Flt2Cur(R);
      ckCur2Fp:
        EmitIns_Cur2Flt(R, typMaps[LT.TypeCode]);
      ckCur2Si:
        EmitIns_Cur2Comp(R);
      ckInt2Bol:
        EmitIns_Int2Bol(R);
      ckBol2Bol:
        EmitIns_Bol2Bol(R, LT.TypeCode);
      ckPtr2Int:
        EmitIns_Ptr2Int(R, typMaps[LT.TypeCode]);
      ckInt2Ptr:
        EmitIns_Int2Ptr(R, TypeStr(LT));
      ckPtr2Ptr:
        EmitBitcast(R, TypeStr(LT));
      ckNone: begin end;
    else
      Assert(False, 'EmitCast, invalid cast');
    end;
  end
  else
  begin

    Assert(False, 'EmitCast');
  end;
end;

procedure TCodeGen.EmitError(const Msg: string;
  const Args: array of const);
begin
  EmitError(Format(Msg, Args));
end;

procedure TCodeGen.EmitError(const Msg: string);
begin
  raise ECodeGenError.Create(Msg);
end;

procedure TCodeGen.EmitError(const Coord: TAstNodeCoord; const Msg: string;
  const Args: array of const);
begin
  EmitError(Format('%s: %d,%d: %s', [
    ExtractFileName(Coord.FileName), Coord.Row, Coord.Col, Format(Msg, Args)
  ]));
end;

procedure TCodeGen.EmitError(const Coord: TAstNodeCoord;
  const Msg: string);
begin
  EmitError(Format('%s: %d,%d: %s', [
    ExtractFileName(Coord.FileName), Coord.Row, Coord.Col, Msg
  ]));
end;

procedure TCodeGen.EmitExpr(const E: TExpr; out Result: TVarInfo);
var
  lbt, rbt: TBaseKind;
begin

  case E.OpCode of
    opNE..opGE, opADD..opSHR:
      begin
        lbt := BaseMaps[TBinaryExpr(E).Left.Typ.TypeCode];
        rbt := BaseMaps[TBinaryExpr(E).Right.Typ.TypeCode];
        case SimpleOpMaps[lbt, rbt] of
          bkBol: EmitOp_Boolean(E, Result);
          bkInt: EmitOp_Int(E, Result);
          bkBig: EmitOp_Int64(E, Result);
          bkFlt: EmitOp_Float(E, Result);
          bkCur: EmitOp_Currency(E, Result);
        else
          Assert(False);
        end;
      end;

    opMEMBER: EmitOp_Member(TBinaryExpr(E), Result);
    opADDR: EmitOp_Addr(TUnaryExpr(E), Result);
    opINST: EmitOp_Inst(TUnaryExpr(E), Result);
    opCAST: EmitOp_Cast(TBinaryExpr(E), Result);
    opCALL: EmitOp_Call(TBinaryExpr(E), Result);
    opINDEX: EmitOp_Index(TBinaryExpr(E), Result);
    opNOT: EmitOp_Not(TUnaryExpr(E), Result);
    opNEG: EmitOp_Neg(TUnaryExpr(E), Result);
    opPOS: EmitExpr(TUnaryExpr(E).Operand, Result);
    opSYMBOL: EmitOp_Load(TSymbolExpr(E), Result);

    opNIL:
      begin
        Result.Name := 'null';
        Result.TyStr := 'i8*';
        Result.States := [vasAddrValue];
      end;
    opBOOLCONST, opINTCONST, opREALCONST:
      EmitOp_LoadConst(TConstExpr(E), Result);
  else
    Assert(False, 'EmitExpr');
  end;

end;

procedure TCodeGen.EmitExternalDecl;

  procedure EmitExternalVarDecl(V: TVariable);
  begin
    WriteDecl(Format('@%s = external global %s', [
        MangledName(V), TypeStr(V.VarType)
      ]));
  end;

  procedure EmitExternalTypeDecl(T: TType);
  begin
    case T.TypeCode of
      typClass: EmitRtti_Class_External(TClassType(T));
    end;
  end;
var
  I: Integer;
  Sym: TSymbol;
begin
  for I := 0 to FExternalDecls.Count - 1 do
  begin
    Sym := TSymbol(FExternalDecls.Keys[I]);
    case Sym.NodeKind of
      nkVariable: EmitExternalVarDecl(TVariable(Sym));
      nkType: EmitExternalTypeDecl(TType(Sym));
    end;
  end;
  // ����. ��������
  // ���RTTI
//  Name := MangledName(Sym);
//  case Sym.NodeKind of
//  // @__my__ = external global i16
//    nkVariable: Decl := Format('@%s = external global %s',
//      [Name, TypeStr(TVariable(Sym).VarType)]);
//    nkType: Self.EmitTypeDecl(TType(Sym));
//  end;

end;

procedure TCodeGen.EmitExternals;
var
  sr: TSystemRoutine;
  typ: TTypeCode;
begin
  for sr := Low(TSystemRoutine) to High(TSystemRoutine) do
  begin
    if sr in FSysRoutines then
      WriteDecl('declare ' + FuncDecl(FContext.GetSystemRoutine(sr), False));
  end;

  // SystemԤ�������͵�����
  for typ := typShortint to typOleVariant do
  begin
    WriteDecl('@System.%s.$typeinfo = external global i8*',
        [ ast.TypeNames[typ] ]
      );
  end;

  EmitExternalDecl;
end;

procedure TCodeGen.EmitFunc(Func: TFunctionDecl);

  function AddRefRoutine(typ: TTypeCode): string;
  begin
    case typ of
      typAnsiString: Result := '@System._AStrAddRef';
      typWideString: Result := '@System._WStrAddRef';
      typUnicodeString: Result := '@System._UStrAddRef';
      typDynamicArray: Result := '@System._DynArrayAddRef';
      typInterface, typDispInterface: Result := '@System._IntfAddRef';
      typVariant, typOleVariant: Result := '@System._VarAddRef';
    else
      Assert(False, 'AddRefFuncName');
    end;
  end;

  procedure ArgInit(Arg: TArgument);
  var
    ty, s: string;
    align: Byte;
  begin
    if not (saUsed in Arg.Attr) then Exit;

    ty := TypeStr(Arg.ArgType);
    align := Arg.ArgType.AlignSize;
    if FCurCntx.NeedFrame and (asNestRef in Arg.States) then
    begin
      if asByRef in Arg.States then
      begin
        s := TempVar;
        WriteCode('%s = getelementptr %s* %%.fp, i32 0, i32 %d', [
          s, FCurCntx.FrameTyStr, Arg.Index
        ]);
        WriteCode('store %s* %%%s.addr, %s** %s', [
          ty, Arg.Name, ty, s
        ]);
      end
      else
        WriteCode('%%%s.addr = getelementptr %s* %%.fp, i32 0, i32 %d', [
          Arg.Name, FCurCntx.FrameTyStr, Arg.Index
        ])
    end
//    else if asByRef in Arg.States then
//    begin
//      WriteCode('%%%s.addr = alloca %s*, align %d', [
//        Arg.Name, ty, FModule.PointerSize
//      ])
//    end
    else if not (asByRef in Arg.States) then
    begin
      WriteCode('%%%s.addr = alloca %s, align %d', [
        Arg.Name, ty, align
      ]);
    end
    else
      Exit;

    if asStructValue in Arg.States then
    begin
      // �ṹ��������ֵ���롣ֻ����ָ�롣�ں���ջ�н���һ��������Ȼ�������ݡ�
      // LLVM���Ż���δ��롣
      // call void @llvm.memcpy.p0i8.p0i8.i32 i8* %arg.addr, i8* %arg, i32 size, 1
      EmitIns_memcpy(ty + '*',
                      '%' + Arg.Name + '.addr',
                      ty + '*',
                      '%' + Arg.Name,
                      Arg.ArgType.Size);

      case Arg.ArgType.TypeCode of
        typRecord, typObject:
          if staNeedInit in TRecordType(Arg.ArgType).RecordAttr then
          begin
            s := TempVar;
            WriteCode('%s = bitcast %s* %%%s.addr to i8*', [s, ty, Arg.Name]);
            WriteCode('call %s void @System._RecordAddRef(i8* %s, i8* bitcast(%%%s.$.init* @%s.$init to i8*))', [
              DefCC, s, Arg.ArgType.Name, Arg.ArgType.Name
            ]);
          end;

        typArray:
          if staNeedInit in TArrayType(Arg.ArgType).ArrayAttr then
          begin
            s := TempVar;
            WriteCode('%s = bitcast %s* %%%s.addr to i8*', [s, ty, Arg.Name]);
            WriteCode('call %s void @System._ArrayAddRef(i8* %s, i8* bitcast(%%%s.$.init* @%s.$init to i8*))', [
              DefCC, s, Arg.ArgType.Name, Arg.ArgType.Name
            ]);
          end;

        typVariant, typOleVariant:
          begin
            WriteCode('call %s void @System._VarCopy(%System.TVarData* %%%s.addr, %System.TVarData* %%%s)', [
              DefCC, Arg.Name, Arg.Name
            ]);
          end;
      end;
    end
//    else if asByRef in Arg.States then
//    begin
//      WriteCode('store %s* %%%s, %s** %%%s.addr', [
//        ty, Arg.Name, ty, Arg.Name
//      ]);
//    end
    else if not (asByRef in Arg.States) then
    begin
      // store i8* %arg, i8** %arg.addr
      WriteCode('store %s %%%s, %s* %%%s.addr', [
        ty, Arg.Name, ty, Arg.Name
      ]);

      case Arg.ArgType.TypeCode of
        typAnsiString, typWideString, typUnicodeString,
        typInterface, typDispInterface, typDynamicArray:
          if Arg.Modifier = argDefault then
          begin
            s := TempVar;
            WriteCode('%s = bitcast %s* %%%s.addr to i8*', [
                s, ty, Arg.Name
            ]);
            WriteCode('call %s void %s(i8* %s)', [
                DefCC, AddRefRoutine(Arg.ArgType.TypeCode), s
            ]);
          end;
      end;
    end;
    WriteCode('');
  end;

  procedure VarInit(V: TVariable);
  var
    s, ty: string;
  begin
    if not (saUsed in V.Attr) then Exit;

    if not (vaLocal in V.VarAttr) then
    begin
      Self.EmitGlobalVarDecl(V);
      Exit;
    end;

    ty := TypeStr(V.VarType);

    if FCurCntx.NeedFrame and (vsNestRef in V.States) then
    begin
      if vsResultAddr in V.States then
      begin
        s := TempVar;
        WriteCode('%s = getelementptr %%%s.$frame* %%.fp, i32 0, i32 %d', [
          s, FCurCntx.MangledName, V.Index
        ]);
        WriteCode('store %s* %Result.addr, %s** %s', [
          ty, ty, s
        ]);
      end
      else
        WriteCode('%%%s.addr = getelementptr %%%s.$frame* %%.fp, i32 0, i32 %d', [
          V.Name, FCurCntx.MangledName, V.Index
        ])
    end
    else if not (vsResultAddr in V.States) and not (vaSelf in V.VarAttr) then
    begin
      WriteCode('%%%s.addr = alloca %s, align %d', [
        V.Name, ty, V.VarType.AlignSize
      ]);
    end
    else
      Exit;

//    if vsResultAddr in V.States then Exit;

    case V.VarType.TypeCode of
      typAnsiString, typWideString, typUnicodeString,
      typInterface, typDispInterface, typDynamicArray:
        begin
          // ��ʼ��Ϊnull
          WriteCode('store %s null, %s* %%%s.addr', [
            ty, ty, V.Name
          ]);
        end;

      typShortString:
        begin
        // ����1�ֽ���0
          s := TempVar;
          WriteCode('%s = bitcast %s* %%%s.addr to i8*', [
            s, ty, V.Name
          ]);
          WriteCode('store i8 0, i8* %s', [ s ]);
        end;

      typVariant, typOleVariant:
        begin
        // ��ǰ4����Ϊ0
          s := TempVar;
          WriteCode('%s = bitcast %s* %%%s.addr to i32*', [
            s, ty, V.Name
          ]);
          WriteCode('store i32 0, i32* %s', [ s ]);
        end;

      typRecord:
        if staNeedInit in TRecordType(V.VarType).RecordAttr then
        begin      // typinfo
          s := TempVar;
          WriteCode('%s = bitcast %s* %%%s.addr to i8*', [s, ty, V.Name]);
          WriteCode('call %s void @System._RecordInit(i8* %s, i8* bitcast(%%%s.$.init* @%s.$init to i8*))', [
            DefCC, s, V.Name, V.Name
          ]);
        end;

      typArray:
        if staNeedInit in TArrayType(V.VarType).ArrayAttr then
        begin
          // ����������Ϣ
          s := TempVar;
          WriteCode('%s = bitcast %s* %%%s.addr to i8*', [s, ty, V.Name]);
          WriteCode('call %s void @System._ArrayInit(i8* %s, i8* bitcast(%%%s.$.ti* @%s.$ti to i8*))', [
            DefCC, s, V.Name, V.Name
          ]);
        end;
    end;
    WriteCode('');
  end;

  procedure WriteLocalInit(Func: TFunction);
  var
    i, parentLevel: Integer;
    Sym: TSymbol;
    Va1, parentFrame: String;
    parentCntx: TEmitFuncContext;
  begin
    if (FCurCntx.Level > 0) and FCurCntx.NeedFrame then
    begin
      parentLevel := FCurCntx.Level - 1;
      parentFrame := TEmitFuncContext(FCntxList[parentLevel]).FrameTyStr;
      // ������һ����ջ��
      Va1 := TempVar;
      WriteCode('%s = getelementptr %s* %%.fp, i32 0, i32 %d', [
        Va1, FCurCntx.FrameTyStr, FCurCntx.LinkedFrameIndex
      ]);
      WriteCode('store %s* %%.fp%d, %s** %s', [
        parentFrame, FCurCntx.Level - 1, parentFrame, Va1
      ]);

      // ��ȡ�����ϼ��ĺ�������,����Ϊ%.fp<Func.Level>
      for i := parentLevel - 1 downto 0 do
      begin
        Va1 := TempVar;
        parentCntx := TEmitFuncContext(FCntxList[i + 1]);
        WriteCode('%s = getelementptr %s* %%.fp%d, i32 0, i32 %d', [
          Va1, parentCntx.FrameTyStr, i + 1, parentCntx.LinkedFrameIndex
        ]);
        parentCntx := TEmitFuncContext(FCntxList[i]);
        WriteCode('%%.fp%d = load %s** %s', [
          i, parentCntx.FrameTyStr, Va1
        ]);
      end;

      // ������Self����,Ҳȡ����,��������
      parentCntx := TEmitFuncContext(FCntxList[0]);
      if Assigned(parentCntx.SelfVar) then
      begin
        Va1 := TempVar;
        WriteCode('%s = getelementptr %s* %%.fp0, i32 0, i32 %d', [
          Va1, parentCntx.FrameTyStr, parentCntx.SelfVar.Index
        ]);
        WriteCode('%.Self = load char** %s', [Va1]);
      end;
    end;

    for i := 0 to Func.LocalSymbols.Count - 1 do
    begin
      Sym := Func.LocalSymbols[i];
      case Sym.NodeKind of
        nkVariable: VarInit(TVariable(Sym));
        nkArgument: ArgInit(TArgument(Sym));
      end;
    end;
  end;

  function CleanupName(typ: TTypeCode): string;
  begin
    case typ of
      typAnsiString: Result := '@System._AStrClr';
      typWideString: Result := '@System._WStrClr';
      typUnicodeString: Result := '@System._UStrClr';
      typInterface, typDispInterface: Result := '@System._IntfClear';
      typVariant, typOleVariant: Result := '@System._VarClear';
    else
      Assert(False, 'CleanupName');
    end;
  end;

  procedure LocalFree(const Name: string; T: TType);
  var
    ty, s: string;
  begin
    ty := TypeStr(T);
    case T.TypeCode of
      typAnsiString, typWideString, typUnicodeString,
      typInterface, typDispInterface, typVariant, typOleVariant:
        begin
          s := TempVar;
          WriteCode('%s = bitcast %s* %%%s.addr to i8*', [
            s, ty, Name
          ]);
          WriteCode('call %s void %s(i8* %s)', [
            DefCc, CleanupName(T.TypeCode), s
          ]);
        end;

      typDynamicArray:
        begin
          s := TempVar;
          WriteCode('%s = bitcast %s* %%%s.addr to i8*', [
            s, ty, Name
          ]);
          WriteCode('call %s void @System._DynArrayClear(i8* %s, i8* bitcast(%%%s.$.ti* @%s.$ti to i8*))', [
            DefCC, s, T.Name, T.Name
          ]);
        end;

      typRecord:
        if staNeedInit in TRecordType(T).RecordAttr then
        begin      // typinfo
          // ת��
          s := TempVar;
          WriteCode('%s = bitcast %s* %%%s.addr to i8*', [s, ty, Name]);
          // �ͷ�
          WriteCode('call %s void @System._RecordFree(i8* %s, i8* bitcast(%%%s.$.init* @%s.$init to i8*))', [
            DefCC, s, T.Name, T.Name
          ]);
        end;

      typArray:
        if staNeedInit in TArrayType(T).ArrayAttr then
        begin
          // todo 1: Need impl
        end;
    end;
  end;

  procedure ArgFree(Arg: TArgument);
  begin
    if not (saUsed in Arg.Attr) then Exit;
    //if Arg.Modifier <> argDefault then Exit;
    if not (asNeedFree in Arg.States) then Exit;

    LocalFree(Arg.Name, Arg.ArgType);
  end;

  procedure VarFree(V: TVariable);
  begin
//    if not (saUsed in V.Attr) then Exit;
    if not (vaLocal in V.VarAttr) then Exit;
    if not (vsNeedFree in V.States) then Exit;
    LocalFree(V.Name, V.VarType);
  end;

  procedure WriteLocalFree(Func: TFunction);
  var
    i: Integer;
    Sym: TSymbol;
  begin
    for i := 0 to Func.LocalSymbols.Count - 1 do
    begin
      Sym := Func.LocalSymbols[i];
      case Sym.NodeKind of
        nkVariable: VarFree(TVariable(Sym));
        nkArgument: ArgFree(TArgument(Sym));
      end;
    end;
  end;

  procedure CheckLocal(Func: TFunction);
  var
    i: Integer;
    Sym: TSymbol;
    Arg: TArgument;
    V: TVariable;
    NestRef: Boolean;
  begin
    NestRef := False;
    for i := 0 to Func.LocalSymbols.Count -1 do
    begin
      Sym := Func.LocalSymbols[i];
      if not (saUsed in Sym.Attr) then Continue;

      case Sym.NodeKind of
        nkFunc, nkMethod: NestRef := True; // ֻҪ��Ƕ�׵ĺ���,��Ҫ����

        nkVariable:
          if vaLocal in TVariable(Sym).VarAttr then
          begin
            V := TVariable(Sym);
            if vaResult in V.VarAttr then
            begin
              if FCurCntx.RetConverted then
                Include(V.States, vsResultAddr);
              FCurCntx.ResultVar := V;
            end
            else if vaSelf in V.VarAttr then
            begin
              FCurCntx.SelfVar := V
            end
            else
            begin
              if NeedInit(V.VarType) then
                Include(V.States, vsNeedInit);
              if NeedFree(V.VarType) then
                Include(V.States, vsNeedFree);
            end;
            if vsNestRef in V.States then
              NestRef := True;
          end;

        nkArgument:
          begin
            Arg := TArgument(Sym);
            if Arg.Modifier in [argOut, argVar] then
              Include(Arg.States, asByRef);

            if (Arg.Modifier = argConst) then
            begin
              if (Arg.ArgType.TypeCode = typUntype) then
                Include(Arg.States, asByRef)
              else if IsStructType(Arg.ArgType) then
              begin
                Include(Arg.States, asByRef);
                Include(Arg.States, asStructRef);
              end;
            end;

            if (Arg.Modifier = argDefault) then
            begin
              if IsStructType(Arg.ArgType) then
                Include(Arg.States, asStructValue);
              if NeedInit(Arg.ArgType) then
                Include(Arg.States, asNeedAddRef);
              if NeedFree(Arg.ArgType) then
              begin
                Include(Arg.States, asNeedFree);
                Include(Arg.States, asNestRef);  // ��Ҫ�����ͷŴ���
              end;
            end;

            if asNestRef in Arg.States then
              NestRef := True;
          end;
      end;
    end;

    FCurCntx.NeedFrame := NestRef or (FCurCntx.Level > 0);
  end;

  procedure SetupLocal(Func: TFunction);
  var
    i: Integer;
    fpIndex: Word;
    fpAlign, typAlign: Byte;
    fpSize: Cardinal;
    offset: Cardinal;
    sf: string;
    Sym: TSymbol;
    Arg: TArgument;
    V: TVariable;

    procedure AdjustAlign(T: TType);
    begin
      typAlign := T.AlignSize;
      if typAlign > fpAlign then
        fpAlign := typAlign;
      if typAlign > 1 then
      begin
        offset := (offset + typAlign - 1) and not (typAlign - 1);
        if offset > fpSize then
        begin
          // ���
          sf := sf + Format('[%d x i8], ', [offset - fpSize]);
          Inc(fpIndex);
        end;
      end;
      Inc(offset, T.Size);
      fpSize := offset;
    end;
  begin
    fpIndex := 0;
    fpSize := 0;
    fpAlign := 0;
    offset := 0;
    for i := 0 to Func.LocalSymbols.Count - 1 do
    begin
      Sym := Func.LocalSymbols[i];
      if not (saUsed in Sym.Attr) then Continue;

      case Sym.NodeKind of
        nkVariable:
          if vsNestRef in TVariable(Sym).States then
          begin
            V := TVariable(Sym);
            adjustAlign(V.VarType);
            V.Index := fpIndex;
            Inc(fpIndex);
            if vsResultAddr in V.States then
              sf := sf + TypeStr(V.VarType) + '*, '
            else
              sf := sf + TypeStr(V.VarType) + ', ';
          end;
        nkArgument:
          if asNestRef in TArgument(Sym).States then
          begin
            Arg := TArgument(Sym);
            adjustAlign(Arg.ArgType);
            Arg.Index := fpIndex;
            Inc(fpIndex);
            if (Arg.ArgType.TypeCode = typOpenArray) then
              Inc(fpIndex); // %args.high
            if asByRef in Arg.States then
              sf := sf + TypeStr(Arg.ArgType) + '*, '
            else
              sf := sf + TypeStr(Arg.ArgType) + ', ';
            if (Arg.ArgType.TypeCode = typOpenArray) then
              sf := sf + 'i32, '; // High(args)
          end;
      end;
    end;

    if FCurCntx.Level > 0 then
    begin
      Assert(FCurCntx.Func.Parent.NodeKind in [nkFunc, nkMethod]);
      sf := sf + Format('%s*, ', [
          TEmitFuncContext(FCntxList[FCurCntx.Level - 1]).FrameTyStr
        ]);
      if fpAlign < FModule.PointerSize then
        fpAlign := FModule.PointerSize;
    end
    else if FCurCntx.NeedFrame and (sf = '') then
    begin
      // ����ûʲô������Ҫ����frame, ��Ƕ�׺�����Ҫ�ϼ���frameָ��,
      // �򴴽�һ�����õ�frame, llvm�����Ż���
      sf := sf + 'i32, ';
      fpAlign := 4;
    end;

    if sf <> '' then
    begin
      Delete(sf, Length(sf) - 1, 2);

      FCurCntx.FrameDecl := Format('%%%s.$frame = type <{%s}>', [
        FCurCntx.MangledName, sf
      ]);
      FCurCntx.FrameTyStr := Format('%%%s.$frame', [FCurCntx.MangledName]);
      FCurCntx.FrameAlign := fpAlign;
    end;
  end;

  procedure WriteFrameDecl;
  begin
    WriteDecl(FCurCntx.FrameDecl);
    WriteCode('%%.fp = alloca %%%s.$frame, align %d', [
      MangledName(Func), FCurCntx.FrameAlign]);
  end;

  procedure WriteRet;
  var
    s: string;
    V: TVariable;
  begin
    if FCurCntx.ExitLabel <> '' then
    begin
      WriteCode('br label %' + FCurCntx.ExitLabel);
      WriteLabel(FCurCntx.ExitLabel);
    end;

    V := FCurCntx.ResultVar;
    if FCurCntx.IsSafecall then
      WriteCode('ret i32 0')
    else if (V = nil) or FCurCntx.RetConverted then
      WriteCode('ret void')
    else begin
      s := TempVar;
      WriteCode('%s = load %s* %%Result.addr', [
        s, TypeStr(V.VarType)
      ]);
      WriteCode('ret %s %s', [TypeStr(V.VarType), s]);
    end;
  end;

  procedure WriteNested(F: TFunction);
  var
    i: Integer;
    sym: TSymbol;
  begin
    for i := 0 to F.LocalSymbols.Count - 1 do
    begin
      sym := F.LocalSymbols[i];
      case sym.NodeKind of
        nkFunc: EmitFunc(TFunction(sym));
        nkMethod, nkExternalFunc: Assert(False, 'WriteNested');
      end;
    end;
  end;

  procedure WriteCtorEntry;
  var
    Va1,  FunTy: string;
  begin
    {
      if flag > 0 then
        pSelf := NewInstance;
      try
        inherited Create(pSelf, 0, args);
        if flag <> 0 then
          AfterConstructor;
      except
        if flag <> 0 then
          FreeInstance;
        raise;
      end;
    }
    Va1 := TempVar;
    WriteCode('%s = icmp ugt i8 %%.flag, 0', [Va1]);
    WriteCode('br i1 %s, label %%ctor.alloc, label %%ctor.noalloc', [Va1]);
    WriteLabel('ctor.alloc');
    // Now %.Self is vmt ptr
    EmitLoadVmtCast('%.Self', 'i8*', False, FNewInstanceFunc, Va1, FunTy);

//    Va2 := TempVar;
    // call fastcc <ret_ty> <ptr>(arg)
    // ����FNewInstanceFunc
    WriteCode('%%.ctor.inst = call %s i8* %s(i8* %%.Self)', [
        CCStr(FNewInstanceFunc.CallConvention), Va1
    ]);
    WriteCode('store i8* %%.ctor.inst to i8** %%Result.addr');
    WriteCode('br %ctor.end');
    WriteLabel('ctor.noalloc');
    WriteCode('store i8* %%.Self to i8** %%Result.addr');
    WriteCode('br %ctor.end');
    WriteLabel('ctor.end');

    FLandingpads.Add('ctor.lpad');
  end;

  procedure WriteCtorExit;
  var
    Va1: string;
  begin
  (*
lpad:
  %0 = landingpad { i8*, i32 } personality i8* bitcast (i32 (...)* @__gxx_personality_v0 to i8* )
          catch i8* null
  %.1 = extractvalue { i8*, i32 } %0, 0
  %.2 = extractvalue { i8*, i32 } %0, 1
  call void @_handle(i8* %.1, i32 %.2) noreturn
  unreachable
  *)
    WriteLabel('ctor.lpad');
    Va1 := TempVar;
    WriteCode(Va1 + ' = landingpad {i8*, i32} personality i8* bitcast(i32(...)* @__gxx_personality_v0 to i8*)');
    WriteCode('   catch i8* null');
    WriteCode('%%.ctor.ex = extractvalue {i8*, i32} %s, 0', [ Va1 ]);
    WriteCode('call fastcc void @System._HandleCtorExcept(i8* %.ctor.ex, i8* %.ctor.inst, i8 %.flag) noreturn');
    WriteCode('unreachable');
    FLandingpads.Delete(FLandingpads.Count - 1);
  end;

  procedure WriteCtorAfter;
  var
    Va, FunTy, L1: string;
  begin
    // Now %.ctor.inst is instance of class
    EmitLoadVmtCast('%.ctor.inst', 'i8*', True,
      FAfterConstructionFunc, Va, FunTy);
    L1 := Self.LabelStr;
    WriteCode('invoke %s void %s(i8* %%.ctor.inst) to label %s unwind label %%ctor.lpad', [
       CCStr(FAfterConstructionFunc.CallConvention),
       Va, L1
    ]);
    WriteLabel(L1);
  end;
var
  OldCntx: TEmitFuncContext;
  LinkAttr: string;
begin
  if Func.NodeKind = nkExternalFunc then
  begin
    if TExternalFunction(Func).FileName <> '' then
    begin
      Assert(TExternalFunction(Func).RoutineName <> '', 'emitFunc');
      WriteCode('declare dllimport ' + FuncDecl(Func, False, TExternalFunction(Func).RoutineName));
    end
    else
      WriteCode('declare ' + FuncDecl(Func, False));
    WriteCode('');
    Exit;
  end;

  OldCntx := FCurCntx;
  FCurCntx := TEmitFuncContext.Create;
  try
    FCntxList.Add(FCurCntx); 
    FCurCntx.Func := TFunction(Func);
    FCurCntx.Level := TFunction(Func).Level;
    FCurCntx.MangledName := MangledName(Func);
    FCurCntx.IsMeth := (Func.NodeKind = nkMethod) and not (saStatic in Func.Attr);
    FCurCntx.IsCtor := (Func.NodeKind = nkMethod) and (TMethod(Func).MethodKind = mkConstructor);
    FCurCntx.IsDtor := (Func.NodeKind = nkMethod) and (TMethod(Func).MethodKind = mkDestructor);
    FCurCntx.IsSafecall := Func.CallConvention = ccSafecall;
    FCurCntx.RetConverted := not FCurCntx.IsCtor and not FCurCntx.IsDtor
                        and Assigned(Func.ReturnType)
                        and IsSpecialType(Func.ReturnType)
                        or FCurCntx.IsSafecall;

    CheckLocal(FCurCntx.Func);
    SetupLocal(TFunction(Func));
    if saInternal in Func.Attr then LinkAttr := 'internal ';
    WriteCode('define ' + LinkAttr + FuncDecl(Func, True));
    WriteCode('{');
    if FCurCntx.NeedFrame then
      WriteFrameDecl;
    WriteLocalInit(TFunction(Func));
    if FCurCntx.IsCtor then
      WriteCtorEntry;

    EmitStmt(TFunction(Func).StartStmt);

    if FCurCntx.IsCtor then
      WriteCtorAfter;

    WriteLocalFree(TFunction(Func));
    WriteRet;
    if FCurCntx.IsCtor then
      WriteCtorExit;
    WriteCode('}');
    WriteCode('');

    WriteNested(TFunction(Func));
  finally
    FCurCntx.Free;
    FCurCntx := OldCntx;
    if FCntxList.Count > 0 then
      FCntxList.Delete(FCntxList.Count - 1);
  end;
end;

procedure TCodeGen.EmitFuncCall(E: TBinaryExpr; Fun: TFunctionDecl;
  FunT: TProceduralType; var Result: TVarInfo);
var
  Count, I: Integer;
  LV, ArgV: TVarInfo;
  ArgE: TExpr;
  Arg: TArgument;
  RetVar, RetTyStr, ArgStr,
  FunName, SelfPtr, {FunPtr, }Va1, Va2: string;
  ParentT: TType;
  IsMeth, IsVirtual, IsSafecall,
  IsNested, IsCtor, IsDtor, RetConv: Boolean;
  CC: TCallingConvention;
  parentCntx: TEmitFuncContext;
begin
// 1.ĳЩ����������Ҫ�ѷ��ؽ���������һ����������,��string
// ������Ҫ���븳ֵ��������ʽ.

// 2.method��Ҫ����Self
// 3.���캯��,���������ж����������

  Count := FunT.CountOfArgs;
  IsMeth := FunT.IsMethodPointer;
  IsSafecall := FunT.CallConvention = ccSafeCall;
  RetConv := Assigned(FunT.ReturnType)
              and IsSpecialType(FunT.ReturnType) or IsSafecall;

  if Assigned(Fun) then
  begin
    IsNested := Fun.Level > 0;
    IsVirtual := (Fun.NodeKind = nkMethod) and (fmVirtual in Fun.Modifiers);
    IsCtor := (Fun.NodeKind = nkMethod) and (TMethod(Fun).MethodKind = mkConstructor);
    IsDtor := (Fun.NodeKind = nkMethod) and (TMethod(Fun).MethodKind = mkDestructor);
  end
  else
  begin
    IsNested := False;
    IsVirtual := False;
    IsCtor := False;
    IsDtor := False;
  end;

{
  obj.test;
  tmyobj(p^).test;
  TMyClass.classProc;
  ClassArray[0].classProc;
}

// Selfָ������Ϊ i8*

  if Fun <> nil then
  begin
    FunName := '@' + MangledName(Fun);
    // get Self pointer
    if IsMeth then
    begin
      Assert(Fun.Parent.NodeKind = nkType, 'Method parent err');

      ParentT := TType(Fun.Parent);
      if E.Left.OpCode = opSYMBOL then
      begin
        LV.Name := '%.Self';
        LV.TyStr := 'i8*';
        LV.States := [];
      end
      else if E.Left.OpCode = opMEMBER then
      begin
        EmitExpr(TBinaryExpr(E.Left).Left, LV);
        if ParentT.TypeCode in [typInterface, typDispInterface, typClass] then
          EmitOp_VarLoad(LV);
        EnsurePtr(LV.TyStr, 'Instance of method is not ptr');
      end
      else
        Assert(False, 'EmitFuncCall, invalid left node'); // ������Ӧ�ò����ܵ�

      // instance.classProc;
      if (ParentT.TypeCode = typClass) and (saClass in Fun.Attr)
          and not (TBinaryExpr(E.Left).Left.IsTypeSymbol) then
      begin
        // ��ʵ�������෽��,��ȡ������vmt
        // ������object֮�಻��Ҫ��������,��Ϊ���ǵ�class��������Ҫ����vmt
        if LV.TyStr <> 'i8**' then
        begin
          Va1 := TempVar;
          WriteCode('%s = bitcast %s %s to i8**', [
            Va1, LV.TyStr, LV.Name
          ]);
        end
        else
          Va1 := LV.Name;
        Va2 := TempVar;
        WriteCode('%s = load i8** %s', [Va2, Va1]);
        LV.Name := Va2;
        LV.TyStr := 'i8*';
        LV.States := [];
      end;

      if IsVirtual or (ParentT.TypeCode in [typInterface, typDispInterface]) then
      begin
      // �����麯��
        if not (saClass in Fun.Attr) then
        begin
          if LV.TyStr <> 'i8***' then
          begin
            Va1 := TempVar;
            WriteCode('%s = bitcast %s %s to i8***', [
              Va1, LV.TyStr, LV.Name
            ]);
          end
          else
            Va1 := LV.Name;

          if parentT.TypeCode = typObject then
          begin
            // ����object,����vmt���Ǵ��ڿ�ͷ
            Va2 := TempVar;
            WriteCode('%s = getelementptr i8*** %s, %%SizeInt %d', [
              Va2, Va1, TObjectType(parentT).VmtOffset div FModule.PointerSize
            ]);
            Va1 := Va2;
          end;

          // load vmt
          Va2 := TempVar;
          WriteCode('%s = load i8*** %s', [Va2, Va1]);
        end
        else
        begin
          Va2 := TempVar;
          WriteCode('%s = bitcast %s %s to i8**', [Va2, LV.TyStr, LV.Name]);
        end;

        // ����, Va2 �Ѿ���vmt, type is i8**
        Va1 := TempVar;
        WriteCode('%s = getelementptr i8** %s, %%SizeInt %d', [
          Va1, Va2, TMethod(Fun).VTIndex
        ]);

        Va2 := TempVar;
        WriteCode('%s = load i8** %s', [Va2, Va1]);

        // va2 is func ptr, type is i8*, cast it to function type
        Va1 := TempVar;
        WriteCode('%s = bitcast i8* %s to %s', [
          Va1, Va2, Self.ProcTypeStr(FunT)
        ]);

        FunName := Va1;
      end;

      if LV.TyStr <> 'i8*' then
      begin
        Va1 := TempVar;
        WriteCode('%s = bitcast %s %s to i8*', [Va1, LV.TyStr, LV.Name]);
        SelfPtr := Va1;
      end
      else
        SelfPtr := LV.Name;

    end;
  end
  else
  begin
    EmitExpr(E.Left, LV);
    if FunT.IsMethodPointer then
    begin
    // ���Ϊmethod event?
      Va1 := TempVar;
      WriteCode('%s = getelementptr [2 x i8*]* %s, i32 0, i32 1', [
        Va1, LV.Name
      ]);
      Va2 := TempVar;
      WriteCode('%s = load i8** %s', [Va2, Va1]);
      SelfPtr := Va2;

      Va1 := TempVar;
      WriteCode('%s = getelementptr [2 x i8*]* %s, i32 0, i32 0', [
        Va1, LV.Name
      ]);
      Va2 := TempVar;
      WriteCode('%s = load i8** %s', [Va2, Va1]);

      LV.Name := TempVar;
      LV.TyStr := Self.ProcTypeStr(FunT);
      WriteCode('%s = bitcast i8* %s to %s', [
        LV.Name, Va2, LV.TyStr
      ]);

      FunName := LV.Name;
    end
    else
    begin
      EmitOp_VarLoad(LV);
      FunName := LV.Name;
    end; 
  end;

  ArgStr := '';

  if IsMeth then Inc(Count);
  if RetConv then Inc(Count);
  if IsNested then Inc(Count);
  if IsCtor then Inc(Count);
  if IsDtor then Inc(Count);
  
  if Count > 0 then
  begin
    if IsMeth then
    begin
      ArgStr := Format('i8* %s, ', [SelfPtr]);
    end;

    if IsCtor then
    begin
    // todo 1: �����Ҫ�������ʽ�Ƿ���ʵ�����Լ��Ƿ�����Χ
      ArgStr := ArgStr + 'i8 1, '
    end;

    if IsDtor then
      ArgStr := ArgStr + 'i8 1, ';

    if IsNested then
    begin
      VarInfoInit(ArgV);
      parentCntx := TEmitFuncContext(FCntxList[Fun.Level - 1]);
      if parentCntx.Level = FCurCntx.Level then
        ArgStr := ArgStr + Format('%s* %%.fp, ', [parentCntx.FrameTyStr])
      else
        ArgStr := ArgStr + Format('%s* %%.fp%d, ', [
          parentCntx.FrameTyStr, parentCntx.Level
        ]);
    end;

    if E.Right = nil then
      ArgE := nil
    else
      ArgE := TUnaryExpr(E.Right).Operand;

    for I := 0 to FunT.CountOfArgs - 1 do
    begin
      Arg := TArgument(FunT.Args[I]);
      VarInfoInit(ArgV);
      if ArgE <> nil then
      begin
        EmitExpr(ArgE, ArgV);
      end
      else
      begin
        Assert(Arg.DefaultValue.VT <> vtEmpty, 'EmitFuncCall');
        EmitOp_LoadConstValue(Arg.DefaultValue, Arg.ArgType, ArgV);
      end;

      if not (IsStructType(Arg.ArgType) or (Arg.Modifier in [argOut, argVar])) then
      begin
        EmitOp_VarLoad(ArgV);        
      end;

      if ArgE <> nil then
        EmitCast(ArgV, ArgE.Typ, Arg.ArgType);
      ArgStr := ArgStr + Format('%s %s, ', [ArgV.TyStr, ArgV.Name]);
      if ArgE <> nil then
        ArgE := TExpr(ArgE.Next);
    end;

    // todo 1: ��Ҫȡopenarray�� high
    if RetConv then
    begin
      
    end;
  end;

  if ArgStr <> '' then
    Delete(ArgStr, Length(ArgStr) - 1, 2);

  if IsSafecall then
  begin
    VarInfoInit(Result);
    Result.Name := TempVar;
    Result.TyStr := 'i32';
    RetVar := Result.Name + ' = ';
    RetTyStr := Result.TyStr;
  end
  else if Assigned(FunT.ReturnType) and not RetConv then
  begin
    VarInfoInit(Result);
    Result.Name := TempVar;
    Result.TyStr := TypeStr(FunT.ReturnType);
    RetVar := Result.Name + ' = ';
    RetTyStr := Result.TyStr;
  end
  else
  begin
    RetVar := '';
    RetTyStr := 'void';
  end;

  if IsSafecall then
    CC := ccStdCall
  else
    CC := FunT.CallConvention;

  WriteCode('%scall %s %s %s(%s)', [
    RetVar, CCStr(CC), RetTyStr, FunName, ArgStr
  ]);

  if IsSafecall then
    EmitCallSys(srSafecallCheck, [Result.TyStr], [Result.Name]);
end;

procedure TCodeGen.EmitGlobalVarDecl(V: TVariable);

  function InitValue: string;
  begin
    case V.Value.VT of
      vtEmpty: Result := 'zeroinitializer';
      vtInt: Result := IntToStr(V.Value.VInt);
      vtInt64: Result := IntToStr(V.Value.VInt64);
      vtReal: Result := FloatToStr(V.Value.VReal);
      vtCurr: Result := IntToStr(V.Value.VInt64); // ��Currency��ΪInt64
      vtBool: Result := IntBoolStr[V.Value.VBool];
      vtAChr: Result := IntToStr(Ord(V.Value.VAChr));
      vtWChr: Result := IntToStr(Word(V.Value.VWChr));
    else
      Result := 'zeroinitializer';  // todo 2: ����
    end;
  end;

  procedure EmitAStrVar;
  var
    s: string;
    pub: Boolean;
  begin
    pub := not (saInternal in TSymbol(V).Attr);
    s := MangledName(V);
    if V.Value.VT = vtEmpty then
      WriteDecl(Format('@%s =%s global i8* null', [s, Visibility[pub]]))
    else begin
      EmitAStr(pub, s + '.data', AnsiString(V.Value.VStr));
      //@b1.astr = global i8* getelementptr({i32, i32, [7 x i8]}* @b1.astr.data, i32 0, i32 2, i32 0)
      WriteDecl(Format('@%s = %s global i8* getelementptr({%%SizeInt, %%SizeInt, [%d x i8]}* @%s, i32 0, i32 2, i32 0)',
        [
          s, Visibility[pub], Length(AnsiString(V.Value.VStr)) + 1, s + '.data'
        ]));
    end;
  end;

  procedure EmitWStrVar;
  var
    s: string;
    s2: WideString;
    pub: Boolean;
  begin
    pub := not (saInternal in TSymbol(V).Attr);
    s := MangledName(V);
    WriteDecl(Format('@%s =%s global i8* null', [s, Visibility[pub]]));
    // todo 1:��ӵ���ʼ����
    if V.Value.VT = vtEmpty then
    begin
      if V.Value.VT = vtStr then
        s2 := AnsiString(V.Value.VStr)
      else
        s2 := WideString(V.Value.VWStr);
      EmitWStr(pub, s + '.data', s2);
      AddInitWStr('@' + s, s + '.data',
          Format('{%%SizeInt, %%SizeInt, [%d x i16]}', [Length(s2) + 1])
      );
    end;
  end;

  procedure EmitUStrVar;
  var
    s: string;
    s2: WideString;
    pub: Boolean;
  begin
    pub := not (saInternal in TSymbol(V).Attr);
    s := MangledName(V);
    if V.Value.VT = vtEmpty then
      WriteDecl(Format('@%s =%s global i6* null', [s, Visibility[pub]]))
    else begin
      if V.Value.VT = vtStr then
        s2 := AnsiString(V.Value.VStr)
      else
        s2 := WideString(V.Value.VWStr);
      EmitUStr(pub, s + '.data', s2);
      //@b1.ustr = global i16* getelementptr({i32, i32, [3 x i16]}* @b1.ustr.data, i32 0, i32 2, i32 0)
      WriteDecl(Format('@%s =%s global i16* getelementptr({%%SizeInt, %%SizeInt, [%d x i16]}* @%s, i32 0, i32 2, i32 0)',
        [
          s, Visibility[pub], Length(s2) + 1, s + '.data'
        ]));
    end;
  end;

  procedure EmitSStrVar;
  var
    s, s2: string;
    chCount: Integer;
    pub, isEmpty: Boolean;
  begin
    s := MangledName(V);
    isEmpty := (V.Value.VT = vtEmpty) or (V.Value.VStr = nil);
    pub := not (saInternal in TSymbol(V).Attr);
    if isEmpty then
      s2 := 'zeroinitializer'
    else begin
      chCount := TShortStringType(V.VarType).CharCount;
      s2 := AnsiString(V.Value.VStr);
      if Length(s2) > chCount then
        s2 := Copy(s2, 1, chCount)
      else if Length(s2) < chCount then
        s2 := s2 + StringOfChar(#0, chCount - Length(s2));
      s2 := Chr(Byte(Length(s2))) + s2;
      s2 := Format('c"%s"', [EncodeAStr(s2)]);
    end;
    WriteDecl(Format('@%s = %s unnamed_addr global [%d x i8] %s', [
        s, Visibility[pub], V.VarType.Size, s2
      ]));
  end;

begin
  case V.VarType.TypeCode of
    typAnsiString: EmitAStrVar;
    typWideString: EmitWStrVar;
    typUnicodeString: EmitUStrVar;
    typShortString: EmitSStrVar;
  else
    WriteDecl(Format('@%s =%s global %s %s', [
        MangledName(V), Visibility[saInternal in TSymbol(V).Attr],
        TypeStr(V.VarType), InitValue
      ]));
  end;
end;

procedure TCodeGen.EmitIns_Bit2Bol(var Result: TVarInfo);
var
  Va: string;
begin
  if Result.TyStr = 'i1' then
  begin
    Va := TempVar;
    WriteCode('%s = zext i1 %s to i8', [Va, Result.Name]);
    Result.Name := Va;
    Result.TyStr := 'i8';
    Result.States := [];
  end;
end;

procedure TCodeGen.EmitIns_Bol2Bol(var Result: TVarInfo; typ: TTypeCode);
var
  Va: string;
begin
// bytebool, wordbool, longbool convertion
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, llvmIntTypeStrs, 'EmitIns_Bol2Bol');
{$ENDIF}
  Va := TempVar;
  WriteCode('%s = icmp ne %s 0, %s', [Va, Result.TyStr, Result.Name]);
  Result.Name := TempVar;
  Result.TyStr := typMaps[typ];
  WriteCode('%s = select i1 %s, %s -1, %s 0',
        [Result.Name, Va,  Result.TyStr, Result.TyStr]
      );
  Result.States := [];
end;

procedure TCodeGen.EmitIns_Bol2I1(var Result: TVarInfo);
var
  Va: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, llvmIntTypeStrs, 'EmitIns_Bol2I1');
{$ENDIF}
  if Result.TyStr <> 'i1' then
  begin
    Va := TempVar;
    WriteCode('%s = icmp ne %s 0, %s', [Va, Result.TyStr, Result.Name]);
    Result.Name := Va;
    Result.TyStr := 'i1';
    Result.States := [];
  end;
end;

procedure TCodeGen.EmitIns_Cur2Comp(var Result: TVarInfo);
var
  Va: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, 'i64', 'EmitIns_Cur2Comp');
{$ENDIF}
  EmitIns_Cur2Flt(Result, 'double');
  Va := TempVar;
  WriteCode('%s = call @System._Round(double %s)', [Va, Result.Name]);
  Result.Name := Va;
  Result.TyStr := 'i64';
end;

procedure TCodeGen.EmitIns_Cur2Flt(var Result: TVarInfo;
  const desT: string);
var
  Va, Va2: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, 'i64', 'EmitIns_Cur2Flt');
  EnsureType(desT, llvmFloatTypeStrs, 'EmitIns_Cur2Flt');
{$ENDIF}
  if desT <> Result.TyStr then
  begin
    Va := TempVar;
    WriteCode('%s = sitofp i64 %s to double', [Va, Result.Name]);
    Va2 := TempVar;
    WriteCode('%s = fdiv double %s, 10000.0', [Va2, Va]);
    Result.Name := Va2;
    Result.TyStr := 'double';
    Result.States := [];
  end;
end;

procedure TCodeGen.EmitIns_Flt2Cur(var Result: TVarInfo);
var
  Va: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, llvmFloatTypeStrs, 'EmitIns_Flt2Cur');
{$ENDIF}
  if Result.TyStr = 'i64' then
  begin
    //Include(FSysRoutines,
    EmitIns_FltExt(Result, 'double');
    Va := TempVar;
    WriteCode('%s = fmul double %s, 10000.0', [Va, Result.Name]);
    Result.Name := Va;
    Va := TempVar;

    EmitCallSys(srRound, ['double'], [Result.Name], Va);
    
    Result.Name := Va;
    Result.TyStr := 'i64';
    Result.States := [];
  end;
end;

procedure TCodeGen.EmitIns_FltExt(var Result: TVarInfo; const desT: string);
var
  va: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, llvmFloatTypeStrs, 'EmitIns_FltExt');
  EnsureType(desT, llvmFloatTypeStrs, 'EmitIns_FltExt');
{$ENDIF}
  if desT <> Result.TyStr then
  begin
    va := TempVar;
    WriteCode('%s = fpext %s %s to %s', [va, Result.TyStr, Result.Name, desT]);
    Result.Name := va;
    Result.TyStr := desT;
  end;
end;

procedure TCodeGen.EmitIns_FltTrunc(var Result: TVarInfo;
  const desT: string);
var
  va: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, llvmFloatTypeStrs, 'EmitIns_FltTrunc');
{$ENDIF}
  if desT <> Result.TyStr then
  begin
    va := TempVar;
    WriteCode('%s = fptrunc %s %s to %s', [va, Result.TyStr, Result.Name, desT]);
    Result.Name := va;
    Result.TyStr := desT;
  end;
end;

procedure TCodeGen.EmitIns_Int2Bol(var Result: TVarInfo);
var
  Va: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, llvmIntTypeStrs, 'EmitIns_Int2Bol');
{$ENDIF}
  Va := TempVar;
  WriteCode('%s = icmp ne %s 0, %s', [Va, Result.TyStr, Result.Name]);
  Result.Name := TempVar;
  Result.TyStr := 'i8';
  WriteCode('%s = select i1 %s, %s 1, %s 0',
        [Result.Name, Va,  Result.TyStr, Result.TyStr]
      );
  Result.States := [];
end;

procedure TCodeGen.EmitIns_Int2Cur(var Result: TVarInfo; sign: Boolean);
var
  Va: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, llvmIntTypeStrs, 'EmitIns_Int2Cur');
{$ENDIF}
  EmitIns_IntExt(Result, 'i64', sign);
  Va := TempVar;
  WriteCode('%s = mul i64 %s, 10000', [Va, Result.Name]);
  Result.Name := Va;
  Result.TyStr := 'i64';
  Result.States := [];
end;

procedure TCodeGen.EmitIns_Int2Flt(var Result: TVarInfo;
  const desT: string; sign: Boolean);
var
  va: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, llvmIntTypeStrs, 'EmitIns_Int2Flt');
  EnsureType(desT, llvmFloatTypeStrs, 'EmitIns_Int2Flt');
{$ENDIF}
  if desT <> Result.TyStr then
  begin
    va := TempVar;
    if sign then
      WriteCode('%s = sitofp %s %s to %s', [va, Result.TyStr, Result.Name, desT])
    else
      WriteCode('%s = uitofp %s %s to %s', [va, Result.TyStr, Result.Name, desT]);
    Result.Name := va;
    Result.TyStr := desT;
    Result.States := [];
  end;
end;

procedure TCodeGen.EmitIns_Int2Ptr(var Result: TVarInfo; const desT: string);
var
  Va: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, llvmIntTypeStrs, 'EmitIns_Int2Ptr');
  EnsurePtr(desT, 'EmitIns_Int2Ptr');
{$ENDIF}
  Va := TempVar;
  WriteCode('%s = inttoptr %s %s to %s', [
    Va, Result.TyStr, Result.Name, desT
  ]);
end;

procedure TCodeGen.EmitIns_IntExt(var Result: TVarInfo; const desT: string;
  sign: Boolean);
var
  va: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, llvmIntTypeStrs, 'EmitIns_IntExt');
  EnsureType(desT, llvmIntTypeStrs, 'EmitIns_IntExt');
{$ENDIF}
  if desT <> Result.TyStr then
  begin
    va := TempVar;
    if Sign then
      WriteCode('%s = sext %s %s to %s', [va, Result.TyStr, Result.Name, desT])
    else
      WriteCode('%s = zext %s %s to %s', [va, Result.TyStr, Result.Name, desT]);
    Result.Name := va;
    Result.TyStr := desT;
  end;
end;

procedure TCodeGen.EmitIns_IntTrunc(var Result: TVarInfo;
  const desT: string);
var
  va: string;
begin
{$IFDEF CHECKTYPE}
  EnsureType(Result.TyStr, llvmIntTypeStrs, 'EmitIns_IntTrunc');
  EnsureType(desT, llvmIntTypeStrs, 'EmitIns_IntTrunc');
{$ENDIF}
  if desT <> Result.TyStr then
  begin
    va := TempVar;
    WriteCode('%s = trunc %s %s to %s', [va, Result.TyStr, Result.Name, desT]);
    Result.Name := va;
    Result.TyStr := desT;
  end;
end;

procedure TCodeGen.EmitIns_Memcpy(const desT, desN, srcT, srcN: string;
  len: Int64; vol: Boolean);
var
  s1, s2: string;
begin
  Include(FIntrinsics, llvm_memcpy);

  if desT <> 'i8*' then
  begin
    s1 := TempVar;
    WriteCode(Format('%s = bitcast %s %s to i8*', [ s1, desT, desN ]));
  end else
    s1 := desN;

  if srcT <> 'i8*' then
  begin
    s2 := TempVar;
    WriteCode(Format('%s = bitcast %s %s to i8*', [ s2, srcT, srcN ]));
  end else
    s2 := srcN;

  WriteCode(Format('call void @llvm.memcpy.p0i8.p0i8.i32(i8* %s, i8* %s, i32 %d, i32 1, i1 false)',
    [s1, s2, len]));
end;

procedure TCodeGen.EmitIns_Ptr2Int(var Result: TVarInfo; const desT: string);
var
  Va: string;
begin
{$IFDEF CHECKTYPE}
  EnsurePtr(Result.TyStr, 'EmitIns_Ptr2Int');
  EnsureType(desT, llvmIntTypeStrs, 'EmitIns_Ptr2Int');
{$ENDIF}
  Va := TempVar;
  WriteCode('%s = ptrtoint %s %s to %s', [
    Va, Result.TyStr, Result.Name, desT
  ]);
  Result.Name := Va;
  Result.TyStr := desT;
  // todo 1:  ����Ҫע��
  Result.States := [];
end;

procedure TCodeGen.EmitIntrinsics;
begin
  if llvm_memcpy in FIntrinsics then
  begin
    WriteDecl('declare void @llvm.memcpy.p0i8.p0i8.i32(i8*, i8*, i32, i32, i1)');
    WriteDecl('declare void @llvm.memcpy.p0i8.p0i8.i64(i8*, i8*, i64, i32, i1)');
  end;
  if llvm_memmove in FIntrinsics then
  begin
    WriteDecl('declare void @llvm.memmove.p0i8.p0i8.i32(i8*, i8*, i32, i32, i1)');
    WriteDecl('declare void @llvm.memmove.p0i8.p0i8.i64(i8*, i8*, i64, i32, i1)');
  end;
  if llvm_rint in FIntrinsics then
  begin
    WriteDecl('declare float @llvm.rint.f32(float)');
    WriteDecl('declare double @llvm.rint.f64(double)');
  end;
  if llvm_ovfi8 in FIntrinsics then
  begin
    WriteDecl('declare {i8, i1} @llvm.sadd.with.overflow.i8(i8, i8)');
    WriteDecl('declare {i8, i1} @llvm.uadd.with.overflow.i8(i8, i8)');
    WriteDecl('declare {i8, i1} @llvm.ssub.with.overflow.i8(i8, i8)');
    WriteDecl('declare {i8, i1} @llvm.usub.with.overflow.i8(i8, i8)');
    WriteDecl('declare {i8, i1} @llvm.smul.with.overflow.i8(i8, i8)');
    WriteDecl('declare {i8, i1} @llvm.umul.with.overflow.i8(i8, i8)');
  end;
  if llvm_ovfi16 in FIntrinsics then
  begin
    WriteDecl('declare {i16, i1} @llvm.sadd.with.overflow.i16(i16, i16)');
    WriteDecl('declare {i16, i1} @llvm.uadd.with.overflow.i16(i16, i16)');
    WriteDecl('declare {i16, i1} @llvm.ssub.with.overflow.i16(i16, i16)');
    WriteDecl('declare {i16, i1} @llvm.usub.with.overflow.i16(i16, i16)');
    WriteDecl('declare {i16, i1} @llvm.smul.with.overflow.i16(i16, i16)');
    WriteDecl('declare {i16, i1} @llvm.umul.with.overflow.i16(i16, i16)');
  end;
  if llvm_ovfi32 in FIntrinsics then
  begin
    WriteDecl('declare {i32, i1} @llvm.sadd.with.overflow.i32(i32, i32)');
    WriteDecl('declare {i32, i1} @llvm.uadd.with.overflow.i32(i32, i32)');
    WriteDecl('declare {i32, i1} @llvm.ssub.with.overflow.i32(i32, i32)');
    WriteDecl('declare {i32, i1} @llvm.usub.with.overflow.i32(i32, i32)');
    WriteDecl('declare {i32, i1} @llvm.smul.with.overflow.i32(i32, i32)');
    WriteDecl('declare {i32, i1} @llvm.umul.with.overflow.i32(i32, i32)');
  end;
  if llvm_ovfi64 in FIntrinsics then
  begin
    WriteDecl('declare {i64, i1} @llvm.sadd.with.overflow.i64(i64, i64)');
    WriteDecl('declare {i64, i1} @llvm.uadd.with.overflow.i64(i64, i64)');
    WriteDecl('declare {i64, i1} @llvm.ssub.with.overflow.i64(i64, i64)');
    WriteDecl('declare {i64, i1} @llvm.usub.with.overflow.i64(i64, i64)');
    WriteDecl('declare {i64, i1} @llvm.smul.with.overflow.i64(i64, i64)');
    WriteDecl('declare {i64, i1} @llvm.umul.with.overflow.i64(i64, i64)');
  end;
end;

procedure TCodeGen.EmitLoadVmt(const VmtVar, VmtTy: string;
  IsInst: Boolean; Offset: Integer; out FunPtr: string);
var
  Va1, Va2: string;
begin
  if IsInst then
  begin
    if VmtTy <> 'i8***' then
    begin
      Va1 := TempVar;
      WriteCode('%s = bitcast %s %s to i8***', [Va1, VmtTy, VmtVar]);
    end
    else
      Va1 := VmtVar;

    Va2 := TempVar;
    WriteCode('%s = load i8*** %s', [Va2, Va1]);
  end
  else
  begin
    if VmtVar <> 'i8**' then
    begin
      Va2 := TempVar;
      WriteCode('%s = bitcast %s %s to i8**', [Va2, VmtTy, VmtVar]);
    end
    else
      Va2 := VmtVar;
  end;

  // Now va2 is vmt ptr, type is i8**
  Va1 := TempVar;
  WriteCode('%s = getelementptr i8** %s, %%SizeInt %d', [Va1, Va2, Offset]);
  Va2 := TempVar;
  WriteCode('%s = load i8** %s', [Va2, Va1]);
  // Now va2 is function ptr, type is i8*
  FunPtr := Va2;
end;

procedure TCodeGen.EmitLoadVmtCast(const VmtVar, VmtTy: string;
  IsInst: Boolean; CastFunc: TMethod; out FunPtr, FunTy: string);
var
  Va: string;
begin
  EmitLoadVmt(VmtVar, VmtTy, IsInst, CastFunc.VTIndex, FunPtr);
  FunTy := Self.ProcTypeStr(CastFunc.ProceduralType);
  Va := TempVar;
  WriteCode('%s = bitcast %s %s to %s', [Va, 'i8*', FunPtr, FunTy]);
  FunPtr := Va;
end;

procedure TCodeGen.EmitModule(M: TModule; Cntx: TCompileContext);

  procedure EmitProgramEntry(M: TModule);
  begin
    Self.EmitFunc(M.InitializeFunc);

    // ����main�������������ձ����EXE����Ҫ��
    WriteCode('define i32 @main(i32 %argc, i8** %argv)');
    WriteCode('{');
    // todo 1: ����,����System�еĳ�ʼ������

    WriteCode('call %s void @%s()', [
      CCStr(M.InitializeFunc.CallConvention),
      MangledName(M.InitializeFunc)
    ]);
    WriteCode('ret i32 0');
    WriteCode('}');
  end;

  procedure EmitUnitEntry(M: TModule);
  begin
    if Assigned(M.InitializeFunc) then
      EmitFunc(M.InitializeFunc);
    if Assigned(M.FinalizeFunc) then
      EmitFunc(M.FinalizeFunc);
  end;

  procedure EmitLLVMDecl;
  var
    S: string;
    PtrBits: Integer;
  begin
    // todo 1: ������,�Ժ����
    PtrBits := FModule.PointerSize * 8;
    S := Format('e-p:%d:%d:%d', [PtrBits, PtrBits, PtrBits]);
    S := S + '-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-f80:128:128-v64:64:64-v128:128:128-a0:0:64-f80:32:32';
    case Self.CPU of
      ckX86:     S := S + '-n8:16:32';
      ckX86_64:  S := S + '-n8:16:32:64';
      ckPPC32:   S := S + '-n32';
      ckPPC64:   S := S + '-n32:64';
    else
      S := S + '-n8:16:32';
    end;
    S := S + '-S0';
    WriteDecl('target datalayout = "%s"', [S]);

    WriteDecl('target triple = "i686-pc-mingw32"');
    {
i686-pc-linux-gnu        �� Linux
i386-unknown-freebsd5.3  �� FreeBSD 5.3
i686-pc-cygwin           �� Cygwin on Win32
i686-pc-mingw32          �� MingW on Win32
i386-pc-mingw32msvc      �� MingW crosscompiler on Linux
i686-apple-darwin*       �� Apple Darwin on X86
x86_64-unknown-linux-gnu �� Linux
    }
    WriteDecl('');
  end;

  procedure EmitNativeType;
  begin
    WriteDecl('%%NativeInt = type %s', [Self.NativeIntStr]);
    WriteDecl('%%SizeInt = type %s', [Self.NativeIntStr]);
  end;

  procedure LoadMethods;

    function Get(const S: string): TMethod;
    var
      Sym: TSymbol;
    begin
      Sym := FContext.FTObjectType.FindSymbol(S);
      if not Assigned(Sym) then
        EmitError('TObject.%s not found', [S]);
      if (Sym.NodeKind <> nkMethod) or not (fmVirtual in TMethod(Sym).Modifiers) then
        EmitError('TObject.%s invalid', [S]);
      Result := TMethod(Sym);
    end;
  begin
    FNewInstanceFunc := Get('NewInstance');
    FAfterConstructionFunc := Get('AfterConstruction');
    FFreeInstanceFunc := Get('FreeInstance');
    FBeforeDestructionFunc := Get('BeforeDestruction');
  end;
var
  i: Integer;
  Sym: TSymbol;
begin
  FModule := M;
  FContext := Cntx;

  EmitLLVMDecl;
  EmitNativeType;
  if FModule.Name = 'System' then
    EmitSysTypeInfo;
  LoadMethods;

  for i := 0 to FModule.Symbols.Count - 1 do
  begin
    Sym := FModule.Symbols[i];
    EmitSymbolDecl(Sym);
  end;

  for i := 0 to FModule.InternalSymbols.Count - 1 do
  begin
    Sym := FModule.InternalSymbols[i];
    EmitSymbolDecl(Sym);
  end;
  EmitIntrinsics;
  EmitExternals;

  case M.Kind of
    mkProgram: EmitProgramEntry(M);
    mkUnit: EmitUnitEntry(M);
  else
    Assert(False, 'EmitModule');
  end;
end;

procedure TCodeGen.EmitOp_Addr(E: TUnaryExpr; out Result: TVarInfo);
//var
//  V: TVarInfo;
begin
  EmitExpr(E.Operand, Result);

  // todo 1: ���������⡣x �� @x Ҫ�зֱ�
  if vasAddrOfVar in Result.States then
  begin
    Exclude(Result.States, vasAddrOfVar);
    Include(Result.States, vasAddrValue);
    Exit;
  end;

  Assert(False);
end;

procedure TCodeGen.EmitOp_Boolean(E: TExpr; out Result: TVarInfo);
var
  L, R: TVarInfo;
  lbLeft, lbRight, lbEnd, v, op: string;
begin
  if not (cdBoolEval in E.Switches) and (E.OpCode in [opOR, opAND]) then
  begin
  {
  ���ʽ: (x >= 0) and ( y >= x) �ķ���.
lb_left:
%.1 = icmp sge i32 %x, 0
br i1 %.1, label %lb_right, label %lb_end  ; if true then continue right expr
lb_right:
%.2 = icmp uge i32 %y, %x
br label %lb_end
lb_end:
%.3 = phi i1 [ %.1, %lb_left], [ %.2, %lb_right ]

  ���ʽ: (x >= 0) or ( y >= x) �ķ���.
lb_left:
%.1 = icmp sge i32 %x, 0
br i1 %.1, label %lb_end, label %lb_right ; if true then pass right expr
lb_right:
%.2 = icmp uge i32 %y, %x
br label %lb_end
lb_end:
%.3 = phi i1 [ %.1, %lb_left], [ %.2, %lb_right ]
  }
    lbLeft := Self.LabelStr;
    lbRight := Self.LabelStr;
    lbEnd := Self.LabelStr;
    WriteCode('br label %%%s', [lbLeft]);
    WriteLabel(lbLeft); // start label
    EmitExpr(TBinaryExpr(E).Left, L);
    EmitOp_VarLoad(L);
    EmitIns_Bol2I1(L);
    if E.OpCode = opAND then
      WriteCode('br i1 %s, label %%%s, label %%%s', [
        L.Name, lbRight, lbEnd])
    else
      WriteCode('br i1 %s, label %%%s, label %%%s', [
        L.Name, lbEnd, lbRight]);

    WriteLabel(lbRight);
    EmitExpr(TBinaryExpr(E).Right, R);
    EmitOp_VarLoad(R);
    EmitIns_Bol2I1(R);
    WriteCode('br label %%%s', [lbEnd]);
    WriteLabel(lbEnd);
    // 	%.3 = phi i1 [ %.1, %lb_left], [ %.2, %lb_right ]
    v := TempVar;
    WriteCode('%s = phi i1 [ %s, %%%s], [ %s, %%%s ]', [
      v, L.Name, lbLeft, R.Name, lbRight
    ]);
    Result.Name := v;
    Result.TyStr := 'i1';
    Result.States := [];
  end
  else
  begin
    EmitExpr(TBinaryExpr(E).Left, L);
    EmitExpr(TBinaryExpr(E).Right, R);

    EmitOp_VarLoad(L);
    EmitIns_Bol2I1(L);

    EmitOp_VarLoad(R);
    EmitIns_Bol2I1(R);

    case E.OpCode of
      opAND: op := 'and';
      opOR: op := 'or';
      opXOR: op := 'xor';
    else
      EmitError(E.Coord, 'EmitOp_boolean, Invalid Op');
    end;

    V := TempVar;
    WriteCode('%s = %s i1 %s, %s', [V, op, L.Name, R.Name]);
    Result.Name := V;
    Result.TyStr := 'i1';
    Result.States := [];
  end;                  
end;

procedure TCodeGen.EmitOp_Call(E: TBinaryExpr; var Result: TVarInfo);
var
//  L: TExpr;
  FunT: TProceduralType;
  Ref: TSymbol;
begin
  Ref := E.Left.GetReference;
  if (Ref <> nil) and (Ref.NodeKind = nkBuiltinFunc) then
  begin
    EmitBuiltin(E, TBuiltinFunction(Ref), TUnaryExpr(E.Right), Result);
  end
  else
  begin
    if Ref <> nil then
      FunT := TFunctionDecl(Ref).ProceduralType
    else begin
      Assert(E.Left.Typ.TypeCode = typProcedural);
      FunT := TProceduralType(E.Left.Typ);
    end;
    EmitFuncCall(E, TFunctionDecl(Ref), FunT, Result);
  end;
end;

procedure TCodeGen.EmitOp_Cast(E: TBinaryExpr; out Result: TVarInfo);
var
  SrcE: TExpr;
  V: TVarInfo;
begin
  Assert(E.Right <> nil);
  SrcE := TUnaryExpr(E.Right).Operand;
  Assert(SrcE <> nil);

  EmitExpr(SrcE, V);
  if eaVarCast in E.Attr then
  begin
    Result.Name := TempVar;
    Result.TyStr := TypeStr(E.Typ) + '*';
    WriteCode('%s = bitcast %s %s to %s', [
      Result.Name, V.TyStr, V.Name, Result.TyStr
    ]);
    Result.States := V.States;
  end
  else
  begin
    EmitOp_VarLoad(V, Result);
    EmitCast(Result, SrcE.Typ, E.Typ);
  end;
(*
  if SrcE.Typ.TypeCode = typUntype then
  begin
    // eg: Integer(p^);
    Result.Name := TempVar;
    Result.TyStr := TypeStr(E.Typ) + '*';
    WriteCode('%s = bitcast %s %s to %s', [
      Result.Name, V.TyStr, V.Name, Result.TyStr
    ]);
    Result.States := V.States;
    Exit;
  end;

  {if (vasAddrOfVar in V.States) then
  begin
    // ���ص�ֻ�Ǳ���ָ��, Ҫ��bitcastת������ָ��
    Result.Name := TempVar;
    Result.TyStr := TypeStr(E.Typ) + '*';
    WriteCode('%s = bitcast %s %s to %s', [
      Result.Name, V.TyStr, V.Name, Result.TyStr
    ]);
    Result.States := V.States;
  end
  else }if vasAddrValue in V.States then
  begin
    Assert(E.Typ.IsPointer, 'EmitOp_Cast, expect pointer type');
    Result.Name := TempVar;
    Result.TyStr := TypeStr(E.Typ);
    WriteCode('%s = bitcast %s %s to %s', [
      Result.Name, V.TyStr, V.Name, Result.TyStr
    ]);
    Result.States := V.States;
  end
  else
  begin
//    EmitOp_VarLoad(V);
    EmitCast(V, SrcE.Typ, E.Typ);
  end;   *)
end;

procedure TCodeGen.EmitOp_Currency(E: TExpr; var Result: TVarInfo);
var
  L, R: TVarInfo;
  LT, RT: TType;
  Op, Va: string;
  NeedAdjust: Boolean; // ����cy��˳��������Ҫ������

  procedure MulBy10k(var R: TVarInfo);
  var
    Va: string;
  begin
    Va := TempVar;
    WriteCode('%s = fmul double %s, 10000.0', [Va, R.Name]);
    R.Name := Va;
  end;

  procedure DivBy10k(var R: TVarInfo);
  var
    Va: string;
  begin
    Va := TempVar;
    WriteCode('%s = fdiv double %s, 10000.0', [Va, R.Name]);
    R.Name := Va;                        
  end;

  procedure ToDouble(T: TType; var R: TVarInfo; MulOrDiv: Boolean);
  begin
    case T.TypeCode of
      typShortint..typUInt64, typComp:
        EmitIns_Int2Flt(R, 'double', T.IsSigned);
      typCurrency:
        EmitIns_Int2Flt(R, 'double', True);
    else
      EmitIns_FltExt(R, 'double');
    end;
    if not MulOrDiv and (T.TypeCode <> typCurrency) then
      MulBy10k(R);
  end;

begin
  EmitExpr(TBinaryExpr(E).Left, L);
  EmitExpr(TBinaryExpr(E).Right, R);

  EmitOp_VarLoad(L);
  EmitOp_VarLoad(R);

  if vasCurrConst in L.States then
    LT := FContext.FTypes[typCurrency]
  else
    LT := TBinaryExpr(E).Left.Typ;

  if vasCurrConst in R.States then
    RT := FContext.FTypes[typCurrency]
  else
    RT := TBinaryExpr(E).Right.Typ;

  ToDouble(LT, L, E.OpCode in [opMUL, opFDIV]);
  ToDouble(RT, R, E.OpCode in [opMUL, opFDIV]);

  NeedAdjust := (LT.TypeCode = typCurrency)
                and (RT.TypeCode = typCurrency)
                and (E.OpCode in [opMUL, opFDIV]);

  case E.OpCode of
    opADD: Op := 'fadd';
    opSUB: Op := 'fsub';
    opMUL: Op := 'fmul';
    opFDIV: Op := 'fdiv';
    opNE: Op := 'fcmp une';
    opEQ: Op := 'fcmp ueq';
    opLT: Op := 'fcmp ult';
    opLE: Op := 'fcmp ule';
    opGT: Op := 'fcmp ugt';
    opGE: Op := 'fcmp uge';
  else
    Assert(False, 'EmitOp_Currency');
  end;

  if E.OpCode in [opNE..opGE] then
  begin
    Result.Name := TempVar;
    Result.TyStr := 'i1';
    Result.States := [];
    WriteCode('%s = %s %s %s, %s', [
      Result.Name, Op, 'double', L.Name, R.Name
    ]);
  end
  else
  begin
    va := TempVar;
    WriteCode('%s = %s %s %s, %s', [
      Va, Op, 'double', L.Name, R.Name
    ]);

//    Include(FSysRoutines, sys_math);

    Result.Name := Va;
    Result.TyStr := 'double';
    if NeedAdjust then DivBy10K(Result);

    Result.Name := TempVar;
    Result.TyStr := 'i64';
    Result.States := [];
    EmitCallSys(srRound, ['double'], [Result.Name], Va);
  end;
end;

procedure TCodeGen.EmitOp_Float(E: TExpr; var Result: TVarInfo);
var
  L, R: TVarInfo;
  LT, RT: TType;
  Op: string;
begin
  EmitExpr(TBinaryExpr(E).Left, L);
  EmitExpr(TBinaryExpr(E).Right, R);

  // ��������Ҫ��չ
  LT := TBinaryExpr(E).Left.Typ;
  RT := TBinaryExpr(E).Right.Typ;

  EmitOp_VarLoad(L);
  EmitOp_VarLoad(R);

  if LT.IsInteger or (LT.TypeCode = typComp) then
    EmitIns_Int2Flt(L, 'double', LT.IsSigned)
  else
    EmitIns_FltExt(L, 'double');

  if RT.IsInteger or (RT.TypeCode = typComp) then
    EmitIns_Int2Flt(R, 'double', RT.IsSigned)
  else
    EmitIns_FltExt(R, 'double');

  case E.OpCode of
    opADD: Op := 'fadd';
    opSUB: Op := 'fsub';
    opMUL: Op := 'fmul';
    opFDIV: Op := 'fdiv';
    opNE: Op := 'fcmp une';
    opEQ: Op := 'fcmp ueq';
    opLT: Op := 'fcmp ult';
    opLE: Op := 'fcmp ule';
    opGT: Op := 'fcmp ugt';
    opGE: Op := 'fcmp uge';
  else
    Assert(False, 'EmitOp_Float');
  end;

  Result.Name := TempVar;
  Result.TyStr := 'double';
  Result.States := [];
  WriteCode('%s = %s %s %s, %s', [
    Result.Name, Op, Result.TyStr, L.Name, R.Name
  ]);
end;

procedure TCodeGen.EmitOp_Index(E: TBinaryExpr; out Result: TVarInfo);
var
  L: TVarInfo;
  I, Count: Integer;
  LowRange: Int64;
  Item: TExpr;
  Items: array of TVarInfo;
  Va: string;
  T: TType;

  function GetLowRange(T: TType): Int64;
  begin
    case T.TypeCode of
      typArray:
        Result := TArrayType(T).Range.RangeBegin;
      typAnsiString..typShortString:
        Result := 1;
    else
      Result := 0;
    end;
  end;
begin
  if eaArrayProp in E.Attr then
  begin
    // todo 1: Need impl
    Assert(False);
  end
  else
  begin
    Item := TUnaryExpr(E.Right).Operand;
    Count := CountOf(Item);
    SetLength(Items, Count);
    I := 0;
    while Item <> nil do
    begin
      EmitExpr(Item, Items[I]);
      EmitOp_VarLoad(Items[I]);
      EmitIns_IntExt(Items[I], NativeIntStr, True);
      Inc(I);
      Item := TExpr(Item.Next);
    end;

    EmitExpr(E.Left, L);
    EnsurePtr(L.TyStr, 'EmitOp_Index, left node must be ptr');

    T := E.Left.Typ;
    for I := 0 to High(Items) do
    begin
      if T.TypeCode <> typArray then
        EmitOp_VarLoad(L);

      LowRange := GetLowRange(T);
      if LowRange <> 0 then
      begin
        Va := TempVar;
        WriteCode('%s = sub %s %s, %s', [
          Va, NativeIntStr, Items[I].Name, IntToStr(LowRange)]);
        Items[I].Name := Va;
      end;
      Va := TempVar;
      if T.TypeCode = typArray then
        WriteCode('%s = getelementptr %s %s, %%SizeInt 0, %%SizeInt %s', [
          Va, L.TyStr, L.Name, Items[I].Name
        ])
      else
        WriteCode('%s = getelementptr %s %s, %%SizeInt %s', [
          Va, L.TyStr, L.Name, Items[I].Name
        ]);

      case T.TypeCode of
        typArray: T := TArrayType(T).ElementType;

        typDynamicArray: T := TDynamicArrayType(T).ElementType;

        typAnsiString, typShortString, typPAnsiChar:
          T := FContext.FTypes[typAnsiChar];

        typWideString, typUnicodeString, typPWideChar:
          T := FContext.FTypes[typWideChar];

        typPointer:
          begin
            Assert(not TPointerType(T).IsUntype, 'EmitOp_Index, void ptr');
            T := TPointerType(T).RefType;
          end;
      else
        Assert(False, 'EmitOp_Index, operand can not be index');
      end;
      L.Name := Va;
      L.TyStr := TypeStr(T) + '*';
      L.States := [vasAddrOfVar];
    end;
    Result.Name := L.Name;
    Result.TyStr := L.TyStr;
    Result.States := L.States;
  end;
end;

procedure TCodeGen.EmitOp_Inst(E: TUnaryExpr; out Result: TVarInfo);
begin
  EmitExpr(E.Operand, Result);
  if vasAddrOfVar in Result.States then
  begin
    EmitOp_VarLoad(Result);
    Include(Result.States, vasAddrOfVar);
  end
  else
  begin
    EnsurePtr(Result.TyStr, 'EmitOp_Inst');
    Include(Result.States, vasAddrOfVar);
  end;
end;

procedure TCodeGen.EmitOp_Int(E: TExpr; var Result: TVarInfo);
var
  L, R: TVarInfo;
  LT, RT: TType;
  ExtTy, Op: string;
  diffSign, resultSign: Boolean;

  function ICmpOp(op: TExprOpCode; sign: Boolean): string;
  begin
    case op of
      opNE: Result := 'icmp ne';
      opEQ: Result := 'icmp eq';
      opLT: if sign then Result := 'icmp slt' else Result := 'icmp ult';
      opLE: if sign then Result := 'icmp sle' else Result := 'icmp ule';
      opGT: if sign then Result := 'icmp sgt' else Result := 'icmp ugt';
      opGE: if sign then Result := 'icmp sge' else Result := 'icmp uge';
    else
      Assert(False, 'ICmpOp');
    end;
  end;
begin
  EmitExpr(TBinaryExpr(E).Left, L);
  EmitExpr(TBinaryExpr(E).Right, R);

//  Assert(E.Typ.IsInteger);
  // ��������Ҫ��չ
  LT := TBinaryExpr(E).Left.Typ;
  RT := TBinaryExpr(E).Right.Typ;
  diffSign := LT.IsSigned <> RT.IsSigned;
  resultSign := LT.IsSigned or RT.IsSigned;

  case E.OpCode of
    opSHR: ExtTy := typMaps[LT.TypeCode];

    opAND, opOR, opXOR, opSHL: ExtTy := typMaps[E.Typ.TypeCode];//'i32';
  else
    if diffSign then
    begin
    {  if (LT.Size = 4) and (RT.Size = 4) then
        ExtTy := typMaps[typInt64]
      else
        ExtTy := typMaps[typLongint];}
      ExtTy := typMaps[E.Typ.TypeCode]
    end
    else
      ExtTy := 'i32';  // ͳһ��չ��i32  
  end;

  EmitOp_VarLoad(L);
  EmitOp_VarLoad(R);
  EmitIns_IntExt(L, ExtTy, LT.IsSigned);
  if E.OpCode = opSHR then
  begin
    if RT.Size > LT.Size then
      EmitIns_IntTrunc(R, ExtTy)
    else
      EmitIns_IntExt(R, ExtTy, RT.IsSigned);
  end
  else
    EmitIns_IntExt(R, ExtTy, RT.IsSigned);

  case E.OpCode of
    opADD: Op := 'add';
    opSUB: Op := 'sub';
    opMUL: Op := 'mul';
    opIDIV: Op := 'div';
    opMOD:
      if resultSign then
        Op := 'srem'
      else
        Op := 'urem';
    opAND: Op := 'and';
    opOR: Op := 'or';
    opXOR: Op := 'xor';
    opSHL: Op := 'shl';
    opSHR: Op := 'lshr';
    opNE..opGE: Op := ICmpOp(E.OpCode, resultSign);
  else
    Assert(False, 'EmitOp_Int, invalid op');
  end;

  if (cdOverflowChecks in E.Switches) and (E.OpCode in [opADD, opSUB, opMUL]) then
  begin
    Result.Name := TempVar;
    EmitOp_IntOvf(L, R, Result, E.OpCode, ltI32, LT.IsSigned or RT.IsSigned);
  end
  else if E.OpCode in [opNE..opGE] then
  begin
    Result.Name := TempVar;
    Result.TyStr := 'i1';
    Result.States := [];
  // 0 result, 1 llvm op, 2 ty, 3 op1, 4 op2
    WriteCode('%s = %s %s %s, %s', [Result.Name, Op, ExtTy, L.Name, R.Name]);
  end
  else
  begin
    Result.Name := TempVar;
    Result.TyStr := ExtTy;
    Result.States := [];
  // 0 result, 1 llvm op, 2 ty, 3 op1, 4 op2
    WriteCode('%s = %s %s %s, %s', [Result.Name, Op, Result.TyStr, L.Name, R.Name]);
  end;
end;

procedure TCodeGen.EmitOp_Int64(E: TExpr; var Result: TVarInfo);
var
  L, R: TVarInfo;
  LT, RT: TType;
  //ExtTy: string;
  Signed: Boolean;

  function CmpCond(op: TExprOpCode; sign: Boolean): string;
  begin
    case op of
      opNE: Result := 'ne';
      opEQ: Result := 'eq';
      opLT: if sign then Result := 'slt' else Result := 'ult';
      opLE: if sign then Result := 'sle' else Result := 'ule';
      opGT: if sign then Result := 'sgt' else Result := 'ugt';
      opGE: if sign then Result := 'sge' else Result := 'uge';
    else
      Assert(False, 'CmpCond');
    end;
  end;

(*
 �������ȽϷ�ʽ��
 var
	i1: int64;
	i2: uint64;
begin
	// i1 > i2, i2 < i1
	Result := (i1 > 0) and (i1 > i2);
	// i1 >= i2, i2 <= i1
	Result := (i1 >= 0) and (i1 >= i2);
	// i1 < i2, i2 > i1
	Result := (i1 < 0) or (i1 < i2);
	// i1 <= i2, i2 >= i1
	Result := (i1 <= 0) or (i1 <= i2);
	// i1 <> i2
	Result := (i1 < 0) or (i1 <> i2);
	// i1 = i2
	Result := (i1 >= 0) and (i1 = i2);
end;
*)
  procedure Rel_BigInt;
  var
    pL, pR: ^TVarInfo;
    Op: TExprOpCode;
    cOp, s1, s2: string;
  begin
    if LT.IsSigned then
    begin
      pL := @L;
      pR := @R;
      Op := E.OpCode;
    end
    else
    begin
      pL := @R;
      pR := @L;
      case E.OpCode of
        opLT: Op := opGT;  // a < b  ת b > a
        opLE: Op := opGE;  // a <= b ת b >= a
        opGT: Op := opLT;  // a > b  ת b < a
        opGE: Op := opLE;  // a >= b ת b <= a
      else
        Op := E.OpCode;
      end;
    end;

    if Op in [ opGT, opGE, opEQ ] then
      cOp := 'and'
    else
      cOp := 'or';

    s1 := TempVar;
    s2 := TempVar;
    if Op = opNE then
      WriteCode('%s = icmp slt i64 %s, 0', [s1, pL^.Name])
    else if Op = opEQ then
      WriteCode('%s = icmp sge i64 %s, 0', [s1, pL^.Name])
    else
      WriteCode('%s = icmp %s i64 %s, 0', [s1, CmpCond(Op, True), pL^.Name]);
    WriteCode('%s = icmp %s i64 %s, %s', [s2, CmpCond(Op, False), pL^.Name, pR^.Name]);
    Result.Name := TempVar;
    // 0 var, 1 and/or, 2 op1, 3 op2
    WriteCode('%s = %s i1 %s, %s', [Result.Name, cOp, s1, s2]);
  end;

begin
  EmitExpr(TBinaryExpr(E).Left, L);
  EmitExpr(TBinaryExpr(E).Right, R);

//  Assert(E.Typ.IsInteger);
  // ��������Ҫ��չ
  LT := TBinaryExpr(E).Left.Typ;
  RT := TBinaryExpr(E).Right.Typ;
  Signed := LT.IsSigned or RT.IsSigned;

  EmitOp_VarLoad(L);
  EmitOp_VarLoad(R);

  EmitIns_IntExt(L, 'i64', LT.IsSigned);
  EmitIns_IntExt(R, 'i64', RT.IsSigned);
  Result.Name := TempVar;
  Result.TyStr := 'i64';
  Result.States := [];

//  if E.OpCode in [opIDIV, opMOD] then
//    Include(FSysRoutines, sys_math);

  case E.OpCode of
    opADD..opMUL, opAND, opSHL, opSHR:
      if (cdOverflowChecks in E.Switches) and (E.OpCode in [opADD, opSUB, opMUL]) then
      begin
        EmitOp_IntOvf(L, R, Result, E.OpCode, ltI64, Signed);
      end
      else
      begin
        // %.1 = llvmins i64 %x, %y
        WriteCode('%s = %s i64 %s, %s', [
          Result.Name, ArithOpMaps[E.OpCode], L.Name, R.Name
        ]);
      end;
    opIDIV:
      EmitCallSys(srInt64Div, ['i64', 'i64'], [L.Name, R.Name], Result.Name);

    opMOD:
      EmitCallSys(srInt64Mod, ['i64', 'i64'], [L.Name, R.Name], Result.Name);

    opNE..opGE:
      if LT.IsSigned = RT.IsSigned then
      begin
        WriteCode('%s = icmp %s i64 %s, %s', [
          Result.Name,
          CmpCond(E.OpCode, LT.IsSigned),
          L.Name, R.Name
        ]);
      end
      else
      begin
        Rel_BigInt;
      end;
  else
    Assert(False, 'EmitOp_Int64');
  end;

end;

procedure TCodeGen.EmitOp_IntOvf(var L, R, Result: TVarInfo;
  Op: TAddSubMulOp; Ty: TLLVMIntType; IsSign: Boolean);
const
  OpStr: array[opADD..opMUL, Boolean] of string = (
  {opADD} ('uadd', 'sadd'),
  {opSUB} ('usub', 'ssub'),
          ('', ''), ('', ''),
  {opMUL} ('umul', 'smul')
  );
  llvm_instr: array[TLLVMIntType] of TLLVMIntrinsic = (
    llvm_ovfi8, llvm_ovfi16, llvm_ovfi32, llvm_ovfi64
  );
var
  TyStr, S, Lb1, Lb2: string;
begin
  Assert(Ty <= ltI64);
  Assert(Ty >= ltI8);
  Include(FIntrinsics, llvm_instr[Ty]);
//  Include(FSysRoutines, sys_ovf_check);

  if Result.Name = '' then Result.Name := TempVar;

  TyStr := llvmTypeNames[Ty];
  WriteCode('%s = call {%s, i1} @llvm.%s.with.overflow.%s(%s %s, %s %s)', [
    Result.Name, TyStr, OpStr[Op, IsSign], TyStr, TyStr, L.Name, TyStr, R.Name
  ]);

  S := TempVar;
  Lb1 := LabelStr; // overflow label
  Lb2 := LabelStr; // normal label
  WriteCode('%s = extractvalue {%s, i1} %s, 1', [S, TyStr, Result.Name]);
  WriteCode('br i1 %s, label %%%s, label %%%s', [S, Lb1, Lb2]);
  WriteLabel(Lb1);
  EmitCallSys(srIntOverflow, [], []);
  WriteCode('unreachable');
  WriteLabel(Lb2);
  S := TempVar;
  WriteCode('%s = extractvalue {%s, i1} %s, 0', [S, TyStr, Result.Name]);
  Result.Name := S;
  Result.TyStr := TyStr;
  Result.States := [];
end;

procedure TCodeGen.EmitOp_Load(E: TSymbolExpr; out Result: TVarInfo);
begin
  EmitOp_LoadRef(E.Reference, Result);
end;

procedure TCodeGen.EmitOp_LoadConst(E: TConstExpr; out Result: TVarInfo);
begin
  EmitOp_LoadConstValue(E.Value, E.Typ, Result);
end;

procedure TCodeGen.EmitOp_LoadConstValue(const Value: TValueRec; T: TType;
  out Result: TVarInfo);
begin
  Result.States := [];
  case Value.VT of
    vtInt:
      begin
        Result.Name := IntToStr(Value.VInt);
        Result.TyStr := typMaps[T.TypeCode];
      end;
    vtInt64:
      begin
        Result.Name := IntToStr(Value.VInt64);
        Result.TyStr := 'i64';
      end;
    vtReal:
      begin
        Result.Name := FloatToStr(Value.VReal);
        Result.TyStr := 'double';
      end;
    vtBool:
      begin
        Result.Name := IntBoolStr[Value.VBool];
        Result.TyStr := 'i8';
      end;
    vtCurr:
      begin
        Result.Name := IntToStr(Value.VInt64); // �����ǺϷ���,Currency��Int64ռͬ�����ڴ�
        Result.TyStr := 'i64';
        Result.States := [vasCurrConst];
      end;
    //vtStr
  else
    Assert(False, 'EmitOp_LoadConstValue');
  end;
end;

procedure TCodeGen.EmitOp_LoadRef(Ref: TSymbol; out Result: TVarInfo);

  procedure LoadOutterArg;
  var
    Va: string;
    parentCntx: TEmitFuncContext;
  begin
    Assert(FCurCntx.Func.Level > TArgument(Ref).Level, 'EmitOp_LoadRef, load arg');
    parentCntx := TEmitFuncContext(FCntxList[TArgument(Ref).Level]);
    Va := TempVar;
    WriteCode('%s = getelementptr %s* %%.fp%d, i32 0, i32 %d', [
      Va, parentCntx.FrameTyStr, TArgument(Ref).Level, TArgument(Ref).Index
    ]);

    if asByRef in TArgument(Ref).States then
    begin
      Result.Name := TempVar;
      Result.States := [vasAddrOfVar];
      Result.TyStr := TypeStr(TArgument(Ref).ArgType) + '*';
      WriteCode('%s = load %s* %s', [Result.Name, Result.TyStr, Va]);
    end
    else
    begin
      Result.Name := Va;
      Result.States := [vasAddrOfVar];
      Result.TyStr := TypeStr(TArgument(Ref).ArgType) + '*';
    end;
  end;

  procedure LoadOutterVar;
  var
    parentCntx: TEmitFuncContext;
  begin
    Assert(FCurCntx.Func.Level > TArgument(Ref).Level, 'EmitOp_LoadRef, load var');
    parentCntx := TEmitFuncContext(FCntxList[TArgument(Ref).Level]);
    Result.Name := TempVar;
    Result.States := [vasAddrOfVar];
    Result.TyStr := TypeStr(TVariable(Ref).VarType) + '*';
    WriteCode('%s = getelementptr %s* %%.fp%d, i32 0, i32 %d', [
      Result.Name, parentCntx.FrameTyStr, TVariable(Ref).Level, TVariable(Ref).Index
    ]);
  end;

  procedure LoadClassVmt(T: TClassType);
  var
    QualID: string;
  begin
    QualID := MangledName(T);
    // ��19 ��ʼ�����vmt��֮ǰ��ϵͳ������
    Result.Name := Format('getelementptr(%%%s.$.vmt* @%s.$vmt, i32 0, i32 19)', [
      QualID, QualID
    ]);
    Result.TyStr := 'i8**';
    Result.States := [];
    if T.Module <> FModule then
      FExternalDecls.Add(T, nil);
  end;
var
  T: TType;
begin
{
��������frame:
  �ֲ�������
    %1 = getelementptr %.fp.struct %.fp, i32 0, i32 1
  ������
    out/var/const�ṹ:
      %1 = getelementptr %.fp.struct %.fp, i32 0, i32 1
      %2 = load i32** %1
    ��ͨ��:
      %1 = getelementptr %.fp.struct %.fp, i32 0, i32 1
  Self:
      %1 = getelementptr %.fp.struct %.fp, i32 0, i32 1
      %2 = load i8** %1

û��frame��,������ͬһ����
  �ֲ�����: <var>.addr
  ����:
    <arg>.addr
  Self:
    %.Self
}
  case Ref.NodeKind of
    nkArgument:
      if TArgument(Ref).Level <> FCurCntx.Func.Level then
      begin
        LoadOutterArg;
      end
      else
      begin
        Result.Name := Format('%%%s.addr', [Ref.Name]);
        Result.States := [vasAddrOfVar];
        Result.TyStr := TypeStr(TArgument(Ref).ArgType) + '*';
      end;

    nkVariable:
      if TVariable(Ref).Level <> FCurCntx.Func.Level then
      begin
        LoadOutterVar;
      end
      else if vaSelf in TVariable(Ref).VarAttr then
      begin
        Result.Name := '%.Self';
        Result.TyStr := 'i8*';
        Result.States := [];
      end
      else if (vsResultAddr in TVariable(Ref).States) then
      begin
        Result.Name := '%Result.addr';
        Result.TyStr := TypeStr(TVariable(Ref).VarType) + '*';
        Result.States := [vasAddrOfVar];
      end
      else if vaLocal in TVariable(Ref).VarAttr then
      begin
        Result.Name := '%' + Ref.Name + '.addr';
        Result.TyStr := TypeStr(TVariable(Ref).VarType) + '*';
        Result.States := [vasAddrOfVar];
      end
      else
      begin
        Result.Name := '@' + MangledName(Ref);
        Result.TyStr := TypeStr(TVariable(Ref).VarType) + '*';
        Result.States := [vasAddrOfVar];
        if Ref.Module <> FModule then
          Self.FExternalDecls.Add(Ref, nil);
      end;

    nkField:
      begin
        //Assert(FCurCntx.Func.Parent
        Assert(False); 
      end;

    nkConstant:
      begin
        T := TConstant(Ref).ConstType;
        if T.IsInteger then
        begin
          Result.Name := ValToStr(TConstant(Ref).Value);
          Result.TyStr := TypeStr(T)
        end
        else if T.IsBoolean then
        begin
          Result.Name := BoolStr[ValToBool(TConstant(Ref).Value)];
          Result.TyStr := 'i1';
        end
        else if T.IsReal then
        begin
          Result.Name := ValToStr(TConstant(Ref).Value);
          Result.TyStr := TypeStr(T);
        end
        else
          Assert(False);  // todo 1: �Ժ��ټ�
      end;

    nkType:
      case TType(Ref).TypeCode of
        typClass: LoadClassVmt(TClassType(Ref));
      else
        Assert(False, 'EmitOp_LoadRef, nkType');
      end;
  else
    Assert(False, 'EmitOp_LoadRef');
  end;
end;

procedure TCodeGen.EmitOp_Member(E: TBinaryExpr; out Result: TVarInfo);
var
  LV: TVarInfo;
  Sym: TSymbol;
  Va: string;
begin
  EmitExpr(E.Left, LV);
//  EmitOp_VarLoad(LV);
  Sym := TSymbolExpr(E.Right).Reference;
  case Sym.NodeKind of
    nkField:
      begin
        Va := TempVar;
        Result.Name := TempVar;
        Result.TyStr := TypeStr(E.Typ) + '*';
        Result.States := [vasAddrOfVar];
        WriteCode('%s = getelementptr %s %s, %%SizeInt 0, %%SizeInt %d', [
          Va, LV.TyStr, LV.Name, TField(Sym).Offset
        ]);
        WriteCode('%s = bitcast i8* %s to %s', [
          Result.Name, Va, Result.TyStr
        ]);
      end;
  else
    Assert(False);
  end;
end;

procedure TCodeGen.EmitOp_Neg(E: TUnaryExpr; out Result: TVarInfo);
var
  V: TVarInfo;
begin
  EmitExpr(E.Operand, V);
  EmitOp_VarLoad(V);
  Result.Name := TempVar;
  case E.Typ.TypeCode of
    typShortint..typComp, typCurrency:
      begin
        Result.TyStr := typMaps[E.Operand.Typ.TypeCode];
        Result.States := [];
        WriteCode('%s = sub %s 0, %s', [
          Result.Name, Result.TyStr, V.Name
        ]);
      end;
    typReal48..typExtended:
      begin
        Result.TyStr := typMaps[E.Operand.Typ.TypeCode];
        Result.States := [];
        WriteCode('%s = fsub %s 0.0, %s', [
          Result.Name, Result.TyStr, V.Name
        ]);
      end;
{    typVariant..typOleVariant:
      begin
        Result.TyStr := typMaps[E.Operand.Typ.TypeCode];
        Result.States := [];
        EmitCall('void @System._VarNeg', '', DefCC, '',
          [typMaps[typVariant]], []);
      end;}
  else
    Assert(False, 'EmitOp_Neg');
  end;
end;

procedure TCodeGen.EmitOp_Not(E: TUnaryExpr; out Result: TVarInfo);
var
  V: TVarInfo;
  Va: string;
const
  TrueValues: array[Boolean] of string = ('-1', '1');
begin
  EmitExpr(E.Operand, V);
  EmitOp_VarLoad(v);
  case E.Typ.TypeCode of
    typShortint..typUInt64:
      begin
        Result.Name := TempVar;
        Result.States := [];
        Result.TyStr := typMaps[E.Operand.Typ.TypeCode];
        WriteCode('%s = xor %s %s, -1', [
          Result.Name, Result.TyStr, V.Name
        ]);
      end;
    typBoolean..typLongBool:
      begin
        Va := TempVar;
        WriteCode('; not op');
        WriteCode('%s = icmp ne %s %s, 0', [
          Va, V.TyStr, V.Name
        ]);
        Result.Name := TempVar;
        Result.States := [];
        Result.TyStr := typMaps[E.Operand.Typ.TypeCode];
        WriteCode('%s = select i1 %s, %s 0, %s %s', [
          Result.Name, Va, Result.TyStr, Result.TyStr,
          TrueValues[E.Operand.Typ.TypeCode = typBoolean]
        ]);
      end;
  else
    Assert(False, 'EmitOp_Not');
  end;
end;

procedure TCodeGen.EmitOp_Ptr(E: TExpr; var Result: TVarInfo);
begin
  // add , sub , ptr - ptr
end;

procedure TCodeGen.EmitOp_VarLoad(var Result: TVarInfo);
var
  v: string;
begin
// Result���ֻ�Ǳ�����ַ��������load ���
  if vasAddrOfVar in Result.States then
  begin
    EnsurePtr(Result.TyStr, 'EmitOp_VarLoad, pointer expected');
    v := TempVar;
    WriteCode('%s = load %s %s', [v, Result.TyStr, Result.Name]);
    Result.Name := v;
    RemoveLastChar(Result.TyStr);
    Exclude(Result.States, vasAddrOfVar);
  end;
end;

procedure TCodeGen.EmitOp_VarLoad(const Src: TVarInfo; out Des: TVarInfo);
begin
// Result���ֻ�Ǳ�����ַ��������load ���
  if vasAddrOfVar in Src.States then
  begin
    EnsurePtr(Src.TyStr, 'EmitOp_VarLoad, pointer expected');
    Des.Name := TempVar;
    Des.TyStr := Src.TyStr;
    Des.States := Src.States;
    WriteCode('%s = load %s %s', [Des.Name, Src.TyStr, Src.Name]);
    RemoveLastChar(Des.TyStr);
    Exclude(Des.States, vasAddrOfVar);
  end
  else
  begin
    VarInfoCopy(Src, des);
  end;
end;

procedure TCodeGen.EmitRangeCheck(var V: TVarInfo; RT, LT: TType);

  function GetRange(LT: TType; out LowVal, HighVal: Int64): Boolean;
  var
    RngTyp: TSubrangeType;
  begin
    Result := True;
    case LT.TypeCode of
      typSubrange:
        begin
          LowVal := TSubrangeType(LT).RangeBegin;
          HighVal := TSubrangeType(LT).RangeEnd;
        end;
      typEnum:
        begin
          LowVal := TEnumType(LT).SubrangeType.RangeBegin;
          HighVal := TEnumType(LT).SubrangeType.RangeEnd;
        end;
    else
      RngTyp := FContext.GetSubrangeType(LT.TypeCode);
      if RngTyp <> nil then
      begin
        LowVal := RngTyp.RangeBegin;
        HighVal := RngTyp.RangeEnd;
      end
      else
        Result := False;
    end;
  end;
var
  LowVal, HighVal: Int64;
  Va, Va2, OkLabel, FailLabel: string;
begin
  if not GetRange(LT, LowVal, HighVal) then Exit;

{
L = Longint, R = Int64/UInt64
%offset = add i64 %value, 2147483648      ; $80000000
%flag = icmp ult i64 %offset, 4294967296 ; $100000000
br i1 %flag, label %Ok, label %Fail

L = Longint, R = LongWord.
%flag = icmp sgt i32 %value, -1
br i1 %flag, label %Ok, label %Fail

L = LongWord, R = Int64/UInt64
%flag = icmp ult i64 %value, 4294967296
br i1 %flag, label %Ok, label %Fail

L = LongWord, R = Longint
%flag = icmp sgt i32 %value, -1
br i1 %flag, label %Ok, label %Fail

L = Int64, R = UInt64
%flag = icmp ult i64 %value, 9223372036854775808
br i1 %flag, label %Ok, label %Fail

L < Longint, R = Longint    low=-1, high=25
%offset = add i32 %value, -1
%flag = icmp ule i32 %offset, 26
br i1 %flag, label %Ok, label %Fail

}
  FailLabel := LabelStr;
  OkLabel := LabelStr;

  if not (LT.TypeCode in [typSubrange, typBoolean..typLongBool])
    and (LT.Size = RT.Size) then
  begin
    Va := TempVar;
    WriteCode('%s = icmp sgt i32 %value, -1');
    WriteCode('br i1 %s, label %%%s, label %%%s', [
        Va, OkLabel, FailLabel
      ]);
  end
  else
  begin
    if LowVal <> 0 then
    begin
      Va := TempVar;
      WriteCode('%s = add %s %s, %s', [Va, V.TyStr, V.Name, IntToStr(0 - LowVal)]);
    end
    else
      Va := V.Name;
    Va2 := TempVar;
    WriteCode('%s = icmp ule %s %s, %s', [Va2, V.TyStr, Va, IntToStr(HighVal - LowVal)]);
    WriteCode('br i1 %s, label %%%s, label %%%s', [
        Va2, OkLabel, FailLabel
      ]);
  end;
  WriteLabel(FailLabel);
  EmitCallSys(srOutOfRange, [], []);
  WriteCode('unreachable');
  WriteLabel(OkLabel);
end;

procedure TCodeGen.EmitRtti_Class(T: TClassType);
var
  QualID: string;
  I: Integer;
begin
  QualID := MangledName(T);
  EmitAStr(True, QualID + '.$name', T.Name);
  // vmt
  WriteDecl('%%%s.$.vmt = type [%d x i8*]', [QualID, T.VmtEntries + 19]);
  WriteDecl('@%s.$vmt = global %%%s.$.vmt [', [
    QualID, QualID
  ]);
  // vmtSelfPtr
  WriteDecl('  i8* bitcast(i8** getelementptr(%%%s.$.vmt* @%s.$vmt, i32 0, i32 19) to i8*)',
    [ QualID, QualID ]);
  // Intf table
  WriteDecl('  ,i8* null');
  // Auto table
  WriteDecl('  ,i8* null');
  // Init table
  WriteDecl('  ,i8* null');
  // Type info
  WriteDecl('  ,i8* null');
  // Field table
  WriteDecl('  ,i8* null');
  // Method table
  WriteDecl('  ,i8* null');
  // Dynamic table
  WriteDecl('  ,i8* null');
  // Class name
  WriteDecl('  ,i8* getelementptr({%%SizeInt, %%SizeInt, [%d x i8]}* @%s.$name, i32 0, i32 2, i32 0)',
    [Length(T.Name) + 1, QualID]
  );
  // Instance size
  WriteDecl('  ,i8* inttoptr(%%SizeInt %d to i8*)', [T.ObjectSize]);
  // Parent
  if not Assigned(T.Base) then
    WriteDecl('  ,i8* null')
  else
    WriteDecl('  ,i8* bitcast(i8** getelementptr(%%%0:s.$.vmt* @%0:s.$vmt, i32 0, i32 19) to i8*)',
      [ MangledName(T.Base) ]);

  {
  // SafeCallException
  WriteDecl('  ,i8* null');
  // AfterConstructor
  WriteDecl('  ,i8* null');
  // BeforeDestructor
  WriteDecl('  ,i8* null');
  // Dispatch
  WriteDecl('  ,i8* null');
  // DefaultHandler
  WriteDecl('  ,i8* null');
  // NewInstance
  WriteDecl('  ,i8* null');
  // FreeInstance
  WriteDecl('  ,i8* null');
  // Destroy
  WriteDecl('  ,i8* null'); }

  WriteDecl(';--- vmt start');
  // ���Լ���VMT
  for I := 0 to T.VmtEntries - 1 do
  begin
    if Assigned(T.Vmt[I]) then
      WriteDecl('  ,i8* bitcast(%s @%s to i8*)', [
        ProcTypeStr(T.Vmt[I].ProceduralType),
        MangledName(T.Vmt[I])
      ])
    else
      WriteDecl('  ,i8* null');
  end;
  WriteDecl(']');
end;

procedure TCodeGen.EmitRtti_Class_External(T: TClassType);
var
  QualID: string;
begin
  QualID := MangledName(T);
  // vmt type
  WriteDecl('%%%s.$.vmt = type [%d x i8*]', [QualID, T.VmtEntries + 19]);
  // vmt data
  WriteDecl('@%s.$vmt = external global %%%s.$.vmt', [
    QualID, QualID
  ]);
end;

procedure TCodeGen.EmitRtti_Intf(T: TInterfaceType);
begin

end;

procedure TCodeGen.EmitRtti_Intf_External(T: TInterfaceType);
begin

end;

procedure TCodeGen.EmitRtti_Object(T: TObjectType);
begin

end;

procedure TCodeGen.EmitRtti_Object_External(T: TObjectType);
begin

end;

procedure TCodeGen.EmitRtti_Record(T: TRecordType);
begin

end;

procedure TCodeGen.EmitRtti_Record_External(T: TRecordType);
begin

end;

procedure TCodeGen.EmitStmt(Stmt: TStatement);

  procedure EmitStmt_Block(Stmt: TCompoundStmt);
  var
    i: Integer;
  begin
    for i := 0 to Stmt.Statements.Count - 1do
      EmitStmt(TStatement(Stmt.Statements[i]));  
  end;
begin
  case Stmt.StmtKind of
    skIfStmt: EmitStmt_If(TIfStmt(Stmt));
    skAssignmentStmt: EmitStmt_Assign(TAssignmentStmt(Stmt));
    skCompoundStmt: EmitStmt_Block(TCompoundStmt(Stmt));
    skForStmt: EmitStmt_For(TForStmt(Stmt));
    skWhileStmt: EmitStmt_While(TWhileStmt(Stmt));
    skRepeatStmt: EmitStmt_Repeat(TRepeatStmt(Stmt));
    skCallStmt: EmitStmt_Call(TCallStmt(Stmt));
  else
    Assert(False);
  end;
end;

procedure TCodeGen.EmitStmt_Assign(Stmt: TAssignmentStmt);
var
  LV, RV: TVarInfo;
begin
//  if Stmt.Left.Typ in 
  EmitExpr(Stmt.Right, RV);
  EmitExpr(Stmt.Left, LV);

  EmitOp_VarLoad(RV);

  if (cdRangeChecks in Stmt.Left.Switches)
    and IsRangeCheckNeeded(Stmt.Right.Typ, Stmt.Left.Typ) then
  begin
    EmitRangeCheck(RV, Stmt.Right.Typ, Stmt.Left.Typ);
  end;

  EmitCast(RV, Stmt.Right.Typ, Stmt.Left.Typ);
  if (Stmt.Right.Typ.TypeCode = typBoolean) and (RV.TyStr = 'i1') then
    EmitIns_Bit2Bol(RV);
  WriteCode('store %s %s, %s %s', [
    RV.TyStr, RV.Name, LV.TyStr, LV.Name
  ]);
end;

procedure TCodeGen.EmitStmt_Call(Stmt: TCallStmt);
var
  E: TBinaryExpr;
  V: TVarInfo;
  FunT: TProceduralType;
  Ref: TSymbol;
begin
  E := TBinaryExpr(Stmt.CallExpr);
  Ref := E.Left.GetReference;
  if Assigned(Ref) and (Ref.NodeKind = nkBuiltinFunc) then
    EmitBuiltin(E, TBuiltinFunction(Ref), TUnaryExpr(E.Right), V)
  else begin
    if Assigned(Ref) and (Ref.NodeKind in [nkFunc, nkMethod, nkExternalFunc]) then
    begin
      FunT := TFunctionDecl(Ref).ProceduralType;
      EmitFuncCall(E, TFunctionDecl(Ref), FunT, V);
    end
    else begin
      Assert(E.Left.Typ.TypeCode = typProcedural);
      FunT := TProceduralType(E.Left.Typ);
      EmitFuncCall(E, nil, FunT, V);
    end;

  end;
  {
  if E.Left.Typ.TypeCode <> typProcedural then
    EmitError(E.Left.Coord, 'EmitStmt_Call, not procedural type');
  FunTyp := TProceduralType(E.Left.Typ);
  for i := 0 to FunTyp.CountOfArgs - 1 do
  begin

  end;}
end;

procedure TCodeGen.EmitStmt_For(Stmt: TForStmt);
const
                // Downto    Signed.
  ForCmpOp: array[Boolean, Boolean] of string = (
    // unsigned, signed
{to}     ('ule', 'sle'),
{downto} ('uge', 'sge')
  );
var
  CtrlAddrV, CtrlV, StartV, StopV: TVarInfo;
  CtrlT: TType;
  OldBreak, OldCont, lbStart, lbBody, lbStop, va: string;
begin
  Assert(Stmt.Value.NodeKind in [nkVariable, nkArgument], 'EmitStmt_For');
  EmitExpr(Stmt.Start, StartV);
  EmitExpr(Stmt.Stop, StopV);
  EmitOp_LoadRef(Stmt.Value, CtrlAddrV);
  CtrlT := nil;
  case Stmt.Value.NodeKind of
    nkVariable: CtrlT := TVariable(Stmt.Value).VarType;
    nkArgument: CtrlT := TArgument(Stmt.Value).ArgType;
  else
    Assert(False);
  end;

  EmitOp_VarLoad(StartV);
  EmitOp_VarLoad(StopV);
  EmitCast(StartV, Stmt.Start.Typ, CtrlT);
  EmitCast(StopV, Stmt.Stop.Typ, CtrlT);
  WriteCode('store %s %s, %s %s', [
    StartV.TyStr, StartV.Name, CtrlAddrV.TyStr, CtrlAddrV.Name
  ]);

  lbStart := LabelStr;
  lbBody := LabelStr;
  lbStop := LabelStr;
  OldBreak := Self.FBreakLabel;
  OldCont := Self.FContinueLabel;
  Self.FBreakLabel := lbStop;
  Self.FContinueLabel := lbStart;

  WriteCode('br label %' + lbStart);
  WriteLabel(lbStart);
  EmitOp_VarLoad(CtrlAddrV, CtrlV);
  va := TempVar;
  WriteCode('%s = icmp %s %s %s, %s', [
    va, ForCmpOp[Stmt.Down, CtrlT.IsSigned], CtrlV.TyStr,
    CtrlV.Name, StopV.Name
  ]);
  WriteCode('br i1 %s, label %%%s, label %%%s', [
    va, lbBody, lbStop
  ]);
  WriteLabel(lbBody);
  if Stmt.Stmt <> nil then
    EmitStmt(Stmt.Stmt);

  va := TempVar;
  WriteCode('%s = add %s %s, 1', [va, CtrlV.TyStr, CtrlV.Name]);
  WriteCode('store %s %s, %s %s', [CtrlV.TyStr, va, CtrlAddrV.TyStr, CtrlAddrV.Name]);
  WriteCode('br label %' + lbStart);
  WriteLabel(lbStop);
  Self.FBreakLabel := OldBreak;
  Self.FContinueLabel := OldCont;
end;

procedure TCodeGen.EmitStmt_If(Stmt: TIfStmt);
var
  vi: TVarInfo;
  L1, L2, L3: string;
begin
{
br i1 %boolexpr, label %if_true, %if_false
if_true:
...
br label %if_false
if_false:

��else��:
br i1 %boolexpr, label %if_true, %if_false
if_true:
...
br label %if_end
if_false:
...
br label %if_end
if_end:

}
  EmitExpr(Stmt.Value, vi);
  EmitOp_VarLoad(vi);
  EmitIns_Bol2I1(vi);
  Assert(vi.TyStr = 'i1', 'EmitStmt_If');
  L1 := LabelStr;
  L2 := LabelStr;
  WriteCode('br i1 %s, label %%%s, label %%%s', [
      vi.Name, L1, L2
    ]);
  WriteLabel(L1);
  EmitStmt(Stmt.TrueStmt);
  if Stmt.FalseStmt <> nil then
  begin
    L3 := LabelStr;
    WriteCode('br label %' + L3);
    WriteLabel(L2);
    EmitStmt(Stmt.FalseStmt);
    WriteCode('br label %' + L3);
    WriteLabel(L3);
  end
  else
  begin
    WriteCode('br label %' + L2);
    WriteLabel(L2);
  end;
end;

procedure TCodeGen.EmitStmt_Repeat(Stmt: TRepeatStmt);
var
  V: TVarInfo;
  OldBreak, OldCont, lbBegin, lbEnd: string;
begin
{
br label %repeat.begin
repeat.begin:

... ; loop body
... ; calcute expr
br i1 %loop.condition, label %repeat.begin, label %repeat.end

repeat.end:

}
  lbBegin := LabelStr;
  lbEnd := LabelStr;
  OldBreak := Self.FBreakLabel;
  OldCont := Self.FContinueLabel;
  Self.FBreakLabel := lbEnd;
  Self.FContinueLabel := lbBegin;

  WriteCode('br label %' + lbBegin);
  WriteLabel(lbBegin);

  if Stmt.Stmt <> nil then
    EmitStmt(Stmt.Stmt);

  EmitExpr(Stmt.Condition, V);
  EmitOp_VarLoad(V);
  Self.EmitIns_Bol2I1(V);
  WriteCode('br i1 %s, label %%%s, label %%%s', [
    V.Name, lbBegin, lbEnd
  ]);

  WriteCode('br label %' + lbBegin);
  WriteLabel(lbEnd);

  Self.FBreakLabel := OldBreak;
  Self.FContinueLabel := OldCont;
end;

procedure TCodeGen.EmitStmt_Try(Stmt: TTryStmt);
begin
{
}
end;

procedure TCodeGen.EmitStmt_While(Stmt: TWhileStmt);
var
  V: TVarInfo;
  OldBreak, OldCont, lbBegin, lbEnd, lbBody: string;
begin
{
br label %while.begin
while.begin:
... ; calcute expr

br i1 %loop.condition, label %while.body, label %while.end
while.body:
... ; loop body
br label %while.begin
while.end:

}
  lbBegin := LabelStr;
  lbBody := LabelStr;
  lbEnd := LabelStr;
  OldBreak := Self.FBreakLabel;
  OldCont := Self.FContinueLabel;
  Self.FBreakLabel := lbEnd;
  Self.FContinueLabel := lbBegin;

  WriteCode('br label %' + lbBegin);
  WriteLabel(lbBegin);

  EmitExpr(Stmt.Condition, V);
  EmitOp_VarLoad(V);
  Self.EmitIns_Bol2I1(V);
  WriteCode('br i1 %s, label %%%s, label %%%s', [
    V.Name, lbBody, lbEnd
  ]);

  WriteLabel(lbBody);

  if Stmt.Stmt <> nil then
    EmitStmt(Stmt.Stmt);

  WriteCode('br label %' + lbBegin);
  WriteLabel(lbEnd);

  Self.FBreakLabel := OldBreak;
  Self.FContinueLabel := OldCont;
end;

procedure TCodeGen.EmitSymbolDecl(Sym: TSymbol);
begin
  case Sym.NodeKind of
    nkType:
      EmitTypeDecl(TType(Sym));

    nkVariable:
      EmitGlobalVarDecl(TVariable(Sym));

    nkFunc, nkMethod, nkExternalFunc:
      EmitFunc(TFunctionDecl(Sym));
  end;
end;

procedure TCodeGen.EmitSysTypeInfo;
type
  TTypeKind = (tkUnknown, tkInteger, tkChar, tkEnumeration, tkFloat,
    tkString, tkSet, tkClass, tkMethod, tkWChar, tkLString, tkWString,
    tkVariant, tkArray, tkRecord, tkInterface, tkInt64, tkDynArray,
    tkUnicodeString);
  TOrdType = (otSByte, otUByte, otSWord, otUWord, otSLong, otULong);
  TFloatType = (ftSingle, ftDouble, ftExtended, ftComp, ftCurr);

  procedure EmitIntTypeInfo(const Name: string; tk: TTypeKind;
      ot: TOrdType; MaxV, MinV: Cardinal);
  var
    llvmtyp: string;
  begin
    llvmtyp := Format('<{i8, i8, [%d x i8], i8, i32, i32}>', [Length(Name)]);
    WriteDecl('@System.%s.$typeinfo.data = unnamed_addr constant %s <{'
        + 'i8 %d, i8 %d, [%d x i8] c"%s", i8 %d, i32 %d, i32 %d}>',
      [
        Name, llvmtyp, Ord(tk), Length(name), Length(Name), 
        EncodeAStr(Name, False), Ord(ot), MinV, MaxV
      ]
    );

    WriteDecl('@System.%s.$typeinfo = global i8* bitcast(%s* '
              + '@System.%s.$typeinfo.data to i8*)',
      [
        Name, llvmtyp, Name
      ]);
  end;

  procedure EmitInt64TypeInfo(const Name: string; tk: TTypeKind;
      ot: TOrdType; MaxV, MinV: Int64);
  var
    llvmtyp: string;
  begin
    llvmtyp := Format('<{i8, i8, [%d x i8], i8, i64, i64}>', [Length(Name)]);
    WriteDecl('@System.%s.$typeinfo.data = unnamed_addr constant %s <{'
        + 'i8 %d, i8 %d, [%d x i8] c"%s", i8 %d, i64 %d, i64 %d}>',
      [
        Name, llvmtyp, Ord(tk), Length(name), Length(Name), 
        EncodeAStr(Name, False), Ord(ot), MinV, MaxV
      ]
    );

    WriteDecl('@System.%s.$typeinfo = global i8* bitcast(%s* '
              + '@System.%s.$typeinfo.data to i8*)',
      [
        Name, llvmtyp, Name
      ]);
  end;

  procedure EmitSimple(const Name: string; tk: TTypeKind);
  var
    llvmtyp: string;
  begin
    llvmtyp := Format('<{i8, i8, [%d x i8]}>', [Length(Name)]);
    WriteDecl('@System.%s.$typeinfo.data = unnamed_addr constant %s <{'
        + 'i8 %d, i8 %d, [%d x i8] c"%s"}>',
      [
        Name, llvmtyp, Ord(tk), Length(name), Length(Name), 
        EncodeAStr(Name, False)
      ]
    );

    WriteDecl('@System.%s.$typeinfo = global i8* bitcast(%s* '
              + '@System.%s.$typeinfo.data to i8*)',
      [
        Name, llvmtyp, Name
      ]
    );
  end;
begin
// ��typShortint..typOleVariant������Ϣ
// ���ƹ���: @System.Char.$typeinfo, ����Ϊ i8*

  EmitIntTypeInfo('Shortint', tkInteger, otSByte, $80, $7f);
  EmitIntTypeInfo('Byte', tkInteger, otUByte, 0, 255);
  EmitIntTypeInfo('Smallint', tkInteger, otSWord, $8000, $7fff);
  EmitIntTypeInfo('Word', tkInteger, otUWord, 0, $ffff);
  EmitIntTypeInfo('Longint', tkInteger, otSLong, $80000000, $7fffffff);
  EmitIntTypeInfo('LongWord', tkInteger, otULong, 0, $ffffffff);
  EmitIntTypeInfo('Integer', tkInteger, otSLong, $80000000, $7fffffff);
  EmitIntTypeInfo('Cardinal', tkInteger, otULong, 0, $ffffffff);
  EmitInt64TypeInfo('Int64', tkInt64, otSLong, Int64($8000000000000000), Int64($7fffffffffffffff));
  EmitInt64TypeInfo('UInt64', tkInt64, otULong, 0, Int64($ffffffffffffffff));

  if FContext.FStringType.TypeCode = typAnsiString then
    EmitSimple('String', tkLString)
  else
    EmitSimple('String', tkUnicodeString);

  EmitSimple('AnsiString', tkLString);
  EmitSimple('WideString', tkWString);
  EmitSimple('UnicodeString', tkUnicodeString);
  EmitSimple('Variant', tkVariant);
  EmitSimple('OleVariant', tkVariant);
end;

procedure TCodeGen.EmitTypeDecl(T: TType);

  procedure EmitStructTypeDecl(T: TType);
  begin
    WriteDecl(Format('%%%s = type [%d x i8]', [MangledName(T), Int64(T.Size)]));
  end;

  procedure EmitProcTypeDecl(T: TProceduralType);
  begin
  // ����ָ����һ��TMethod�ṹ
  // TMethod = record Code, Data: Pointer; end;
    if T.IsMethodPointer then
      WriteDecl(Format('%%%s = type [2 x i8*]', [MangledName(T)]))
    else
      WriteDecl(ProcTypeStr(T, MangledName(T)));
  end;

  function ArrayTypeStr(T: TArrayType): string;
  var
    Size: Int64;
  begin
    Size := T.Range.RangeEnd - T.Range.RangeBegin + 1;
    case T.ElementType.TypeCode of
      typArray:
        Result := Format('[%d x %s]', [Size, ArrayTypeStr(TArrayType(T.ElementType))]);
    else
      Result := Format('[%d x %s]', [Size, TypeStr(T.ElementType)]);
    end;
  end;

  procedure EmitArrayTypeDecl(T: TArrayType);
  var
    s: string;
  begin
    s := ArrayTypeStr(T);
    WriteDecl(Format('%%%s = type %s', [MangledName(T), s]));
  end;

var
  I: Integer;
begin
  if FEmittedSymbols.IsExists(T) then Exit;

  case T.TypeCode of
    typClass:
      begin
        // classΪi8*
        EmitRtti_Class(TClassType(T));
        for I := 0 to TClassType(T).Symbols.Count - 1 do
          EmitSymbolDecl(TClassType(T).Symbols[I]);
        FEmittedSymbols.Add(T, nil);
        if Assigned(TClassType(T).Base) then
          Self.FExternalDecls.Add(TClassType(T).Base, nil);
      end;

    typRecord:
      begin
        EmitStructTypeDecl(T);
        EmitRtti_Record(TRecordType(T));
        for I := 0 to TRecordType(T).Symbols.Count - 1 do
          EmitSymbolDecl(TRecordType(T).Symbols[I]);
        FEmittedSymbols.Add(T, nil);
      end;

    typObject:
      begin
        EmitStructTypeDecl(T);
        EmitRtti_Object(TObjectType(T));
        for I := 0 to TObjectType(T).Symbols.Count - 1 do
          EmitSymbolDecl(TObjectType(T).Symbols[I]);
        FEmittedSymbols.Add(T, nil);
        if Assigned(TObjectType(T).Base) then
          FExternalDecls.Add(TObjectType(T).Base, nil);
      end;

    typInterface, typDispInterface:
      begin
        EmitRtti_Intf(TInterfaceType(T));
        FEmittedSymbols.Add(T, nil);
      end;

    typProcedural:
      begin
        EmitProcTypeDecl(TProceduralType(T));
        FEmittedSymbols.Add(T, nil);
      end;

    typArray:
      begin
        EmitArrayTypeDecl(TArrayType(T));
        // typinfo


        FEmittedSymbols.Add(T, nil);
      end;
  end;
end;

procedure TCodeGen.EmitUStr(pub: Boolean; const name: string;
  const s: WideString);
var
  ChCount, ByteCount: Integer;
begin
  ChCount := Length(s) + 1;
  ByteCount := ChCount * 2;
  // 0 name, 1 visibility, 2 char count, 3 byte count, 4 char count, 5 string
  WriteDecl(Format('@%s = %s unnamed_addr global {i32, i32, [%d x i16]} {i32 -1, i32 %d, [%d x i16] [%s]}',
    [
      name, Visibility[pub], ChCount, ByteCount, ChCount, EncodeWStr(s)
    ]));
end;

procedure TCodeGen.EmitWStr(pub: Boolean; const name: string;
  const s: WideString);
var
  ChCount, ByteCount: Integer;
begin
  ChCount := Length(s) + 1;
  ByteCount := ChCount * 2;
  // 0 name, 1 visibility, 2 char count, 3 byte count, 4 char count, 5 string
  WriteDecl(Format('@%s = %s unnamed_addr global {%%SizeInt, [%d x i16]} {%%SizeInt %d, [%d x i16] [%s]}',
    [
      name, Visibility[pub], ChCount, ByteCount, ChCount, EncodeWStr(s)
    ]));
end;

function TCodeGen.FuncDecl(F: TFunctionDecl; NeedArgName: Boolean;
    const Name: string = ''): string;
var
  i: Integer;
  s, ret, n, attr: string;
  Arg: TArgument;
  retConvert, isSafecall, isCtor, isDtor, isMeth: Boolean;
  cc: TCallingConvention;
  parentCntx: TEmitFuncContext;
begin
  // safecallҪ����i32�����Ұ�ԭ�ȷ��ص�(����еĻ�)�������һ������, cc��Ϊstdcall
  // Ҫ�ѷ���string,interface,record,variant�ȵ� ��Ϊ���һ������
  isMeth := (F.NodeKind = nkMethod) and not (saStatic in F.Attr);
  isCtor := (F.NodeKind = nkMethod) and (TMethod(F).MethodKind = mkConstructor);
  isDtor := (F.NodeKind = nkMethod) and (TMethod(F).MethodKind = mkDestructor);
  isSafecall := F.CallConvention = ccSafeCall;
  retConvert := not isCtor and not isDtor and (F.ReturnType <> nil)
               and IsSpecialType(F.ReturnType)
               or isSafecall;
  s := '';
  if isMeth then
  begin
    if NeedArgName then
      s := 'i8* %.Self, '
    else
      s := 'i8*, ';

    if isCtor then
      case TMethod(F).ObjectKind of
        okObject:
          if NeedArgName then
            s := s + '%SizeInt %.vmt, '
          else
            s := s + '%SizeInt, ';
        okRecord, okClass:
          if NeedArgName then
            s := s + 'i8 %.flag, '
          else
            s := s + 'i8, ';
      end;

    if isDtor then
      if NeedArgName then
        s := s + 'i8 %.outterMost, '
      else
        s := s + 'i8, ';
  end
  else if TFunction(F).Level > 0 then
  begin
    parentCntx := TEmitFuncContext(FCntxList[TFunction(F).Level - 1]);
    s := Format('%s* %%.fp%d, ', [
            parentCntx.FrameTyStr,
            parentCntx.Level
          ]);
  end;

  for i := 0 to F.CountOfArgs - 1 do
  begin
    arg := TArgument(F.Args[i]);
    s := s + ArgDeclStr(arg, NeedArgName);

    if (Arg.ArgType.TypeCode = typOpenArray) then
    begin
      s := s + ', i32';
      if NeedArgName then s := s + Format(' %%%s.high, ', [arg.Name]);
    end
    else
      s := s + ', ';
  end;

  if retConvert then
    s := s + TypeStr(F.ReturnType) + '* %Result.addr'
  else if s <> '' then
    Delete(s, Length(s) - 1, 2); // ɾ������

  if isSafecall then
    ret := 'i32'
  else if (F.ReturnType = nil) or retConvert then
    ret := 'void'
  else
    ret := TypeStr(F.ReturnType);

  if Name = '' then
    n := MangledName(F)
  else
    n := Name;

  if fmNoReturn in F.Modifiers then
    attr := 'noreturn'
  else
    attr := '';

  if isSafecall then
    cc := ccStdCall
  else
    cc := F.CallConvention;
  Result := Format('%s %s @%s(%s)%s', [CCStr(cc), ret, n, s, attr]);
end;

function TCodeGen.GetIR: string;
begin
  Result := FDecls.Text + #13#10;
  Result := Result + FCodes.Text;
end;

function TCodeGen.IsRangeCheckNeeded(RT, LT: TType): Boolean;
begin
  Result := False;
  if LT.TypeCode = typSubrange then
  begin
    if RT.TypeCode = typSubrange then
      if TSubrangeType(RT).SubSetOf(TSubrangeType(LT)) then Exit; // ����Ҫ���
  end
  else
    if (LT.IsBoolean) or (RT.TypeCode = LT.TypeCode) or (LT.Size > RT.Size) then Exit;
  Result := True;
end;

function TCodeGen.LabelStr: string;
begin
  Inc(FCurCntx.LabelID);
  Result := 'L' + IntToStr(FCurCntx.LabelID);
end;

function TCodeGen.ProcTypeStr(T: TProceduralType; const Name: string): string;
var
  i: Integer;
  s, ret: string;
  arg: TArgument;
  convResult, isSafecall: Boolean;
begin
  // Ҫ�ѷ���string,interface,record,variant�ȵ� ��Ϊ���һ������
  // safecallҪ����i32�����Ұ�ԭ�ȷ��ص�(����еĻ�)�������һ������
  isSafecall := T.CallConvention = ccSafeCall;
  convResult := (T.MethodKind = mkNormal) and (T.ReturnType <> nil)
               and IsSpecialType(T.ReturnType) or isSafecall;

  s := '';
  if T.IsMethodPointer then
  begin
    s := 'i8*, ';

    if T.MethodKind = mkConstructor then
      case T.ObjectKind of
        okObject:           s := s + '%SizeInt, ';
        okRecord, okClass:  s := s + 'i8, ';
      end;

    if T.MethodKind = mkDestructor then
      s := s + 'i8, ';
  end;

  for i := 0 to T.CountOfArgs - 1 do
  begin
    arg := TArgument(T.Args[i]);
    s := s + ArgTypeStr(arg.ArgType, arg.Modifier) + ', ';
    if Assigned(arg.ArgType) and (arg.ArgType.TypeCode = typOpenArray) then
      s := s + 'i32, ';
  end;

  if convResult then
    s := s + TypeStr(T.ReturnType) + '*'
  else if s <> '' then
    Delete(s, Length(s) - 1, 2); // ɾ������

  if isSafecall then
    ret := 'i32'
  else if (T.ReturnType = nil) or convResult then
    ret := 'void'
  else
    ret := TypeStr(T.ReturnType);

  if Name <> '' then
    Result := Format('%%%s = type %s (%s)*', [Name, ret, s])
  else
    Result := Format('%s (%s)*', [ret, s]);
end;

function TCodeGen.TempVar: string;
begin
  Inc(FCurCntx.TempID);
  Result := '%.' + IntToStr(FCurCntx.TempID);
end;

function TCodeGen.TypeStr(Typ: TType): string;

  function NameStr(T: TType): string;
  begin
  //  if not FEmittedSymbols.IsExists(T) then
      EmitTypeDecl(T);
    Result := '%' + MangledName(T);
  end;

  function RecordTypeStr(T: TRecordType): string;
  begin
    if T.Name <> '' then
      Result := NameStr(T)
    else
      Result := Format('[%d x i8]', [Int64(T.Size)]);
  end;

  function RefTypeStr(T: TType): string;
  begin
    Result := '%' + MangledName(T) + '*'; 
  end;

  function OpenArrayTypeStr(T: TOpenArrayType): string;
  begin
    if T.ElementType.TypeCode <> typUntype then
      Result := TypeStr(T.ElementType) + '*'
    else
      Result := '%System.TVarRec*';
  end;

  function SStrTypeStr(T: TShortStringType): string;
  begin
    Result := Format('[%d x i8]', [T.Size]);
  end;

  function SetStr(T: TSetType): string;
  begin
    if T.Size = 1 then
      Result := 'i8'
    else if T.Size = 2 then
      Result := 'i16'
    else if T.Size = 4 then
      Result := 'i32'
    else
      Result := Format('[%d x i8]', [T.Size]);
  end;

  function PointerStr(T: TPointerType): string;
  begin
    if T.RefType = nil then
      Result := 'i8*'
    else
      Result := TypeStr(T.RefType) + '*';
  end;

  function ArrayTypeStr(T: TArrayType): string;
  var
    Size: Int64;
  begin
    Size := T.Range.RangeEnd - T.Range.RangeBegin + 1;
    Result := Format('[%d x %s]', [Size, TypeStr(T.ElementType)]);
  end;

  function EnumStr(T: TEnumType): string;
  begin
    if T.Size = 1 then
      Result := 'i8'
    else if T.Size = 2 then
      Result := 'i16'
    else
      Result := 'i32';
  end;
begin
// ȡ��������.
// �����record, class, interface, objectֱ��ȡ�Ѿ����������
// ����ǻ������ͣ�ת��llvm��������

  case Typ.TypeCode of
    typShortString:
      Result := SStrTypeStr(TShortStringType(Typ));

    typSubrange:
      Result := TypeStr(TSubrangeType(Typ).BaseType);

    typDynamicArray:
      Result := TypeStr(TDynamicArrayType(Typ).ElementType) + '*';

    typRecord:
      Result := RecordTypeStr(TRecordType(Typ));

    typObject:
      Result := NameStr(typ);

  // ��Щ����ֱ���� typMaps�Ϳ�����
   // typClass, typInterface, typDispInterface: Result := RefTypeStr(Typ);

    typArray:
      Result := ArrayTypeStr(TArrayType(typ));

    typPointer:
      Result := PointerStr(TPointerType(typ));

    typProcedural:
      Result := NameStr(typ);

    typSet:
      Result := SetStr(TSetType(typ));

    typEnum:
      Result := EnumStr(TEnumType(typ));

    typAlias, typClonedType:
      Result := TypeStr(Typ.NormalType);

    typSymbol: Assert(False, 'TypeStr');

    typOpenArray:
      Result := OpenArrayTypeStr(TOpenArrayType(Typ));
  else
    Result := typMaps[Typ.TypeCode];
  end;
end;

function TCodeGen.WriteCode(const S: string): Integer;
begin
  Result := FCodes.Add(S);
end;

function TCodeGen.WriteCode(const S: string;
  const Args: array of const): Integer;
begin
  Result := FCodes.Add(Format(S, Args));
end;

procedure TCodeGen.WriteDecl(const S: string);
begin
  FDecls.Add(S);
end;

procedure TCodeGen.WriteDecl(const S: string; const Args: array of const);
begin
  FDecls.Add(Format(S, Args));
end;

function TCodeGen.WriteLabel(const S: string): Integer;
begin
  Result := FCodes.Add(S + ':');
end;

{ TEmitFuncContext }

procedure TEmitFuncContext.AddTempVar(const Name: string; vt: TAutoInitVarType);
var
  Temp: TTempVarInfo;
begin
  if TempInitVars = nil then
  begin
    TempInitVars := TList.Create;
    TempInitVars.Capacity := 10;
  end;
  Temp := TTempVarInfo.Create;
  Temp.Name := Name;
  Temp.Typ := vt;
  TempInitVars.Add(Temp);
end;

procedure TEmitFuncContext.ClearTempVars;
var
  i: Integer;
begin
  if TempInitVars = nil then Exit;
  for i := 0 to TempInitVars.Count - 1 do
    TObject(TempInitVars[i]).Free;
  TempInitVars.Clear;
end;

destructor TEmitFuncContext.Destroy;
begin
  ClearTempVars;
  TempInitVars.Free;
  inherited;
end;

end.
