unit atsynedit_adapter_litelexer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Dialogs,
  ATSynEdit,
  ATSynEdit_Adapters,
  ATSynEdit_CanvasProc,
  Masks,
  FileUtil,
  at__jsonConf,
  ec_RegExpr;

type
  { TATLiteLexerRule }

  TATLiteLexerRule = class
  public
    Name: string;
    Style: string;
    StyleHash: integer;
    RegexObj: TecRegExpr;
    constructor Create(const AName, AStyle, ARegex: string; ACaseSens: boolean); virtual;
    destructor Destroy; override;
  end;

type
  TATLiteLexer_GetStyleHash = function (Sender: TObject; const AStyleName: string): integer of object;
  TATLiteLexer_ApplyStyle = procedure (Sender: TObject; AStyleHash: integer; var APart: TATLinePart) of object;

type
  { TATLiteLexer }

  TATLiteLexer = class(TATAdapterHilite)
  private
    FOnGetStyleHash: TATLiteLexer_GetStyleHash;
    FOnApplyStyle: TATLiteLexer_ApplyStyle;
  public
    LexerName: string;
    FileTypes: string;
    CaseSens: boolean;
    Rules: TList;
    constructor Create(AOnwer: TComponent); override;
    destructor Destroy; override;
    procedure LoadFromFile(const AFilename: string);
    procedure Clear;
    function IsFilenameMatch(const AFilename: string): boolean;
    function GetRule(AIndex: integer): TATLiteLexerRule;
    function GetDump: string;
    procedure OnEditorCalcHilite(Sender: TObject; var AParts: TATLineParts;
      ALineIndex, ACharIndex, ALineLen: integer; var AColorAfterEol: TColor); override;
    property OnGetStyleHash: TATLiteLexer_GetStyleHash read FOnGetStyleHash write FOnGetStyleHash;
    property OnApplyStyle: TATLiteLexer_ApplyStyle read FOnApplyStyle write FOnApplyStyle;
  end;

type
  { TATLiteLexers }

  TATLiteLexers = class
  private
    FList: TList;
    FOnGetStyleHash: TATLiteLexer_GetStyleHash;
    FOnApplyStyle: TATLiteLexer_ApplyStyle;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure Clear;
    procedure LoadFromDir(const ADir: string);
    function Count: integer;
    function GetLexer(AIndex: integer): TATLiteLexer;
    function FindLexer(AFilename: string): TATLiteLexer;
    property OnGetStyleHash: TATLiteLexer_GetStyleHash read FOnGetStyleHash write FOnGetStyleHash;
    property OnApplyStyle: TATLiteLexer_ApplyStyle read FOnApplyStyle write FOnApplyStyle;
  end;

implementation

{ TATLiteLexers }

constructor TATLiteLexers.Create;
begin
  inherited;
  FList:= TList.Create;
end;

destructor TATLiteLexers.Destroy;
begin
  Clear;
  FreeAndNil(FList);
  inherited;
end;

procedure TATLiteLexers.Clear;
var
  i: integer;
begin
  for i:= FList.Count-1 downto 0 do
    TObject(FList[i]).Free;
  FList.Clear;
end;

function TATLiteLexers.GetLexer(AIndex: integer): TATLiteLexer;
begin
  Result:= TATLiteLexer(FList[AIndex]);
end;

function TATLiteLexers.FindLexer(AFilename: string): TATLiteLexer;
var
  Lexer: TATLiteLexer;
  i: integer;
begin
  Result:= nil;
  AFilename:= ExtractFileName(AFilename);
  for i:= 0 to FList.Count-1 do
  begin
    Lexer:= GetLexer(i);
    if Lexer.IsFilenameMatch(AFileName) then
      exit(Lexer);
  end;
end;

procedure TATLiteLexers.LoadFromDir(const ADir: string);
var
  Files: TStringList;
  Lexer: TATLiteLexer;
  i: integer;
begin
  Files:= TStringList.Create;
  try
    FindAllFiles(Files, ADir, '*.json;*.cuda-litelexer', false);
    Files.Sorted:= true;

    for i:= 0 to Files.Count-1 do
    begin
      Lexer:= TATLiteLexer.Create(nil);
      Lexer.OnGetStyleHash:= FOnGetStyleHash;
      Lexer.OnApplyStyle:= FOnApplyStyle;
      Lexer.LoadFromFile(Files[i]);
      FList.Add(Lexer);
    end;
  finally
    FreeAndNil(Files);
  end;
end;

function TATLiteLexers.Count: integer;
begin
  Result:= FList.Count;
end;

{ TATLiteLexerRule }

constructor TATLiteLexerRule.Create(const AName, AStyle, ARegex: string; ACaseSens: boolean);
begin
  inherited Create;
  Name:= AName;
  Style:= AStyle;
  RegexObj:= TecRegExpr.Create;
  RegexObj.Expression:= ARegex;
  RegexObj.ModifierI:= not ACaseSens;
  RegexObj.ModifierS:= false; //don't catch all text by .*
  RegexObj.ModifierM:= true; //allow to work with ^$
end;

destructor TATLiteLexerRule.Destroy;
begin
  FreeAndNil(RegexObj);
  inherited Destroy;
end;

{ TATLiteLexer }

constructor TATLiteLexer.Create(AOnwer: TComponent);
begin
  inherited;
  Rules:= TList.Create;
end;

destructor TATLiteLexer.Destroy;
begin
  Clear;
  FreeAndNil(Rules);
  inherited;
end;

procedure TATLiteLexer.Clear;
var
  i: integer;
begin
  LexerName:= '?';
  CaseSens:= false;

  for i:= Rules.Count-1 downto 0 do
    TObject(Rules[i]).Free;
  Rules.Clear;
end;

function TATLiteLexer.IsFilenameMatch(const AFilename: string): boolean;
begin
  Result:= MatchesMaskList(AFilename, FileTypes, ';');
end;

function TATLiteLexer.GetRule(AIndex: integer): TATLiteLexerRule;
begin
  Result:= TATLiteLexerRule(Rules[AIndex]);
end;

procedure TATLiteLexer.LoadFromFile(const AFilename: string);
var
  c: TJSONConfig;
  keys: TStringList;
  rule: TATLiteLexerRule;
  s_name, s_regex, s_style: string;
  i: integer;
begin
  Clear;
  if not FileExists(AFilename) then exit;

  c:= TJSONConfig.Create(nil);
  keys:= TStringList.Create;
  try
    try
      c.Filename:= AFileName;
    except
      ShowMessage('Cannot load JSON lexer file:'#10+AFilename);
      exit;
    end;

    LexerName:= ChangeFileExt(ExtractFileName(AFilename), '');
    CaseSens:= c.GetValue('/case_sens', false);
    FileTypes:= c.GetValue('/files', '');

    c.EnumSubKeys('/rules', keys);
    for i:= 0 to keys.Count-1 do
    begin
      s_name:= keys[i];
      s_regex:= c.GetValue('/rules/'+s_name+'/regex', '');
      s_style:= c.GetValue('/rules/'+s_name+'/style', '');
      if (s_name='') or (s_regex='') or (s_style='') then Continue;

      rule:= TATLiteLexerRule.Create(s_name, s_style, s_regex, CaseSens);
      if Assigned(FOnGetStyleHash) then
        rule.StyleHash:= FOnGetStyleHash(Self, rule.Style);

      Rules.Add(rule);
    end;
  finally
    keys.Free;
    c.Free;
  end;
end;

function TATLiteLexer.GetDump: string;
const
  cBool: array[boolean] of string = ('false', 'true');
var
  i: integer;
begin
  Result:=
    'name: '+LexerName+#10+
    'case_sens: '+cBool[CaseSens]+#10+
    'files: '+FileTypes+#10+
    'rules:';
  for i:= 0 to Rules.Count-1 do
    with GetRule(i) do
      Result:= Result+#10+Format('(name: "%s", re: "%s", st: "%s", st_n: %d)',
        [Name, RegexObj.Expression, Style, StyleHash]);
end;


procedure TATLiteLexer.OnEditorCalcHilite(Sender: TObject;
  var AParts: TATLineParts; ALineIndex, ACharIndex, ALineLen: integer;
  var AColorAfterEol: TColor);
var
  Ed: TATSynEdit;
  EdLine: UnicodeString;
  ch: WideChar;
  NParts, NPos, NLen, IndexRule: integer;
  Rule: TATLiteLexerRule;
  bLastFound, bRuleFound: boolean;
begin
  Ed:= Sender as TATSynEdit;
  EdLine:= Copy(Ed.Strings.Lines[ALineIndex], ACharIndex, ALineLen);
  NParts:= 0;
  NPos:= 1;
  bLastFound:= false;

  repeat
    if NPos>Length(EdLine) then Break;
    if NParts>=High(TATLineParts) then Break;
    bRuleFound:= false;

    ch:= EdLine[NPos];
    if (ch<>' ') and (ch<>#9) then
      for IndexRule:= 0 to Rules.Count-1 do
      begin
        Rule:= GetRule(IndexRule);
        NLen:= Rule.RegexObj.MatchLength(EdLine, NPos);
        if NLen>0 then
        begin
          bRuleFound:= true;
          Break;
        end;
      end;

    if not bRuleFound then
    begin
      if (NParts=0) or bLastFound then
      begin
        Inc(NParts);
        AParts[NParts-1].Offset:= NPos-1;
        AParts[NParts-1].Len:= 1;
      end
      else
      begin
        Inc(AParts[NParts-1].Len);
      end;
      AParts[NParts-1].ColorBG:= clNone; //Random($fffff);
      AParts[NParts-1].ColorFont:= clBlack;
      Inc(NPos);
    end
    else
    begin
      Inc(NParts);
      AParts[NParts-1].Offset:= NPos-1;
      AParts[NParts-1].Len:= NLen;
      AParts[NParts-1].ColorBG:= clNone; //Random($fffff);
      if Assigned(FOnApplyStyle) then
        FOnApplyStyle(Self, Rule.StyleHash, AParts[NParts-1]);
      Inc(NPos, NLen);
    end;

    bLastFound:= bRuleFound;
  until false;
end;

end.
