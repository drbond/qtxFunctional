unit form1;

// ---------------------------------------------------------------------------
//  qtxMemoisation - main form
//
//  Standard Quartex controls only: TQTXComboBox, TQTXNumberEdit, TQTXButton,
//  TQTXListBox, TQTXMemo and TQTXPanel. All logic lives in memo.model.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  qtx.classes,
  qtx.components,
  qtx.dom.types,
  qtx.dom.events,
  qtx.dom.graphics,
  qtx.dom.widgets,
  qtx.dom.border,
  qtx.dom.theme,
  qtx.dom.application,
  qtx.dom.forms,
  qtx.dom.events.mouse,
  qtx.dom.events.pointer,
  qtx.dom.events.keyboard,
  qtx.dom.events.touch,
  qtx.dom.control.panel,
  qtx.dom.control.button,
  qtx.dom.control.combobox,
  qtx.dom.control.edit,
  qtx.dom.control.listbox,
  qtx.dom.control.memo,
  functional.functions,
  functional.lazy,
  functional.lazylist,
  memo.model;

type

  Tform1 = class( TQTXForm )
  {$I "intf::form1"}
  private
    // Section 1 - recursion
    FProblem:     TQTXComboBox;
    FN:           TQTXNumberEdit;
    FProblemNote: TQTXPanel;
    FCompare:     TQTXPanel;
    FNaiveTree:   TQTXMemo;
    FMemoTree:    TQTXMemo;
    // Section 2 - lazy values
    FCached:      TLazyValue;
    FUncached:    TLazyValue;
    FLazyStatus:  TQTXPanel;
    FCachedLast:  String;
    FUncachedLast: String;
    // Section 3 - memoised infinite list
    FFibs:        TLazyList;
    FIndex:       TQTXNumberEdit;
    FListStatus:  TQTXPanel;
    FHistory:     TQTXListBox;
    FTotalForced: Integer;

    function  Card(const Title, Intro: String): TQTXPanel;
    function  Section(const Parent: TQTXComponent; const Caption: String): TQTXPanel;
    function  Row(const Parent: TQTXComponent): TQTXPanel;
    function  Block(const Parent: TQTXComponent; const Flex: String): TQTXPanel;
    function  AddButton(const Parent: TQTXComponent; const Caption: String;
      Primary: Boolean): TQTXButton;
    function  TreeMemo(const Parent: TQTXComponent): TQTXMemo;
    function  EditValue(const Edit: TQTXNumberEdit; Default, Lo, Hi: Integer): Integer;

    procedure CompareRecursion;
    procedure NewLazyValues;
    procedure ReadLazy(Cached: Boolean);
    procedure ShowLazyStatus;
    procedure NewFibonacciList;
    procedure ReadFromList;
    procedure BuildUI;
  protected
    procedure FormPresented; override;
    procedure FormHidden; override;

    procedure StyleObject; override;
  public
    constructor Create(AOwner: TQTXComponent; CB: TQTXFormConstructor); override;
    destructor Destroy; override;
end;

implementation

const
  Muted     = '#8a96a3';
  Accent    = '#2f6fb0';
  Warm      = '#d9822b';
  PrimeLimit = 200000;

function Thousands(Value: Float): String;
var
  Digits: String;
  i, Count: Integer;
begin
  Digits := FloatToStr(Round(Value));
  Result := '';
  Count := 0;
  for i := Length(Digits) downto 1 do
  begin
    if (Count > 0) and ((Count mod 3) = 0) and (Digits[i] <> '-') then
      Result := ',' + Result;
    Result := Digits[i] + Result;
    Inc(Count);
  end;
end;

constructor Tform1.Create(AOwner: TQTXComponent; CB: TQTXFormConstructor);
begin
  inherited Create(AOwner, procedure (Form: TQTXForm)
  begin
    {$I "impl::form1"}

    BuildUI;

	if assigned( CB ) then
	  CB( self );
  end);
end;

destructor Tform1.destroy;
begin
  inherited;
end;

{ Layout helpers }

function Tform1.Card(const Title, Intro: String): TQTXPanel;
var
  Heading: String;
begin
  Heading := '<h2 style="margin:0 0 6px 0;font-weight:500;font-size:21px">' + Title + '</h2>' +
    '<div style="color:#555;line-height:1.55;max-width:900px">' + Intro + '</div>';
  Result := TQTXPanel.Create(Self, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.marginTop := '28px';
      Panel.Style.paddingTop := '20px';
      Panel.Style.borderTop := '1px solid #dde4ec';
    end);
  TQTXPanel.Create(Result, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.InnerHtml := Heading;
    end);
end;

function Tform1.Section(const Parent: TQTXComponent; const Caption: String): TQTXPanel;
begin
  Result := TQTXPanel.Create(TQTXDOMComponent(Parent), procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.margin := '14px 0 6px 0';
      Panel.InnerHtml := '<span style="font-size:11px;font-weight:bold;letter-spacing:1px;' +
        'text-transform:uppercase;color:' + Muted + '">' + Caption + '</span>';
    end);
end;

function Tform1.Row(const Parent: TQTXComponent): TQTXPanel;
begin
  Result := TQTXPanel.Create(TQTXDOMComponent(Parent), procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdFlex;
      Panel.Style.flexWrap := 'wrap';
      Panel.Style.alignItems := 'center';
      Panel.Style.columnGap := '8px';
      Panel.Style.marginTop := '10px';
    end);
end;

function Tform1.Block(const Parent: TQTXComponent; const Flex: String): TQTXPanel;
var
  F: String;
begin
  F := Flex;
  Result := TQTXPanel.Create(TQTXDOMComponent(Parent), procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.flex := F;
      Panel.Style.minWidth := '0';
    end);
end;

function Tform1.AddButton(const Parent: TQTXComponent; const Caption: String;
  Primary: Boolean): TQTXButton;
var
  IsPrimary: Boolean;
begin
  IsPrimary := Primary;
  Result := TQTXButton.Create(TQTXDOMComponent(Parent), procedure (Button: TQTXButton)
    begin
      Button.PositionMode := cpStatic;
      Button.InnerHtml := Caption;
      Button.Style.padding := '7px 14px';
      Button.Style.cursor := 'pointer';
      Button.Style.borderRadius := '4px';
      if IsPrimary then
      begin
        Button.Style.backgroundColor := Accent;
        Button.Style.borderColor := Accent;
        Button.Style.color := '#ffffff';
      end;
    end);
end;

function Tform1.TreeMemo(const Parent: TQTXComponent): TQTXMemo;
begin
  Result := TQTXMemo.Create(TQTXDOMComponent(Parent), procedure (Memo: TQTXMemo)
    begin
      Memo.PositionMode := cpStatic;
      Memo.ReadOnly := True;
      Memo.Style.width := '100%';
      Memo.Style.height := '300px';
      Memo.Style.fontFamily := 'Consolas, "Courier New", monospace';
      Memo.Style.fontSize := '12px';
      Memo.Style.lineHeight := '1.5';
      Memo.Style.padding := '10px';
      Memo.Style.border := '1px solid #dde4ec';
      Memo.Style.borderRadius := '4px';
      Memo.Style.boxSizing := 'border-box';
      Memo.Style.whiteSpace := 'pre';
    end);
end;

function Tform1.EditValue(const Edit: TQTXNumberEdit; Default, Lo, Hi: Integer): Integer;
begin
  try
    Result := StrToInt(Edit.Text);
  except
    Result := Default;
  end;
  if Result < Lo then
    Result := Lo;
  if Result > Hi then
    Result := Hi;
  Edit.Text := IntToStr(Result);
end;

{ Building the UI }

procedure Tform1.BuildUI;
var
  C, R, Cols, B: TQTXPanel;
  k: TProblemKind;
begin
  Style.height := '100vh';
  Style.width := '100%';
  Style.padding := '24px 32px 48px 32px';
  Style.overflowY := 'auto';
  Style.fontFamily := 'Ubuntu, "Segoe UI", Roboto, sans-serif';
  Style.color := '#1e2a3a';

  TQTXPanel.Create(Self, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.InnerHtml :=
        '<h1 style="margin:0;font-weight:500;font-size:28px">qtx<b>Memoisation</b></h1>' +
        '<div style="color:#555;margin-top:6px;line-height:1.55;max-width:900px">' +
        'Memoisation means remembering the answer to a computation so it is never worked ' +
        'out twice. It is safe for pure functions, because the same input always gives ' +
        'the same output. Three ways it appears in qtxFunctional:</div>';
    end);

  { 1. Memoised recursion }

  C := Card('1. Naive versus memoised recursion',
    'Each problem below is written once, as a function that calls a <i>Recurse</i> ' +
    'function instead of itself. Run naively, Recurse is the function itself, so the same ' +
    'sub-problems are solved again and again. Memoised, Recurse checks a cache first - a ' +
    'TPersistentMap, so even the cache is immutable.');
  R := Row(C);
  FProblem := TQTXComboBox.Create(R, procedure (Box: TQTXComboBox)
    begin
      Box.PositionMode := cpStatic;
      Box.Style.padding := '6px';
      Box.Style.minWidth := '440px';
    end);
  for k := Low(TProblemKind) to High(TProblemKind) do
    FProblem.Add(TMemoModel.ProblemTitle(k));
  TQTXPanel.Create(R, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdInlineBlock;
      Panel.InnerHtml := '<span style="color:#555">n =</span>';
    end);
  FN := TQTXNumberEdit.Create(R, procedure (Edit: TQTXNumberEdit)
    begin
      Edit.PositionMode := cpStatic;
      Edit.Style.width := '64px';
      Edit.Style.padding := '6px';
      Edit.Text := '20';
    end);
  AddButton(R, 'Compare', True).OnClick := procedure (Sender: TObject)
    begin
      CompareRecursion;
    end;

  FProblemNote := TQTXPanel.Create(C, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.marginTop := '10px';
    end);
  FCompare := TQTXPanel.Create(C, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.marginTop := '6px';
    end);

  Cols := Row(C);
  Cols.Style.alignItems := 'flex-start';
  Cols.Style.columnGap := '20px';
  B := Block(Cols, '1 1 380px');
  Section(B, 'Naive call tree');
  FNaiveTree := TreeMemo(B);
  B := Block(Cols, '1 1 380px');
  Section(B, 'Memoised call tree');
  FMemoTree := TreeMemo(B);

  { 2. Lazy values }

  C := Card('2. Lazy values: cached or recomputed',
    'Both values below hold the same deferred computation - counting the primes up to ' +
    '200,000 by trial division. Nothing runs until a value is read. The cached ' +
    'TLazyValue (call-by-need) works it out on the first read and remembers it; the ' +
    'uncached one (call-by-name) works it out again on every read.');
  R := Row(C);
  AddButton(R, 'Read the cached value', True).OnClick := procedure (Sender: TObject)
    begin
      ReadLazy(True);
    end;
  AddButton(R, 'Read the uncached value', False).OnClick := procedure (Sender: TObject)
    begin
      ReadLazy(False);
    end;
  AddButton(R, 'Start again', False).OnClick := procedure (Sender: TObject)
    begin
      NewLazyValues;
    end;
  FLazyStatus := TQTXPanel.Create(C, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.marginTop := '12px';
    end);

  { 3. Memoised infinite list }

  C := Card('3. A memoised infinite list',
    'The Fibonacci numbers defined in terms of themselves: Fibs = 0, 1, then Fibs added to ' +
    'its own tail. Each cell of a TLazyList is built only when it is first needed, then ' +
    'kept. Ask for a term, then ask for a smaller one, or the same one again: only cells ' +
    'that have never been needed before are computed.');
  R := Row(C);
  TQTXPanel.Create(R, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdInlineBlock;
      Panel.InnerHtml := '<span style="color:#555">Term</span>';
    end);
  FIndex := TQTXNumberEdit.Create(R, procedure (Edit: TQTXNumberEdit)
    begin
      Edit.PositionMode := cpStatic;
      Edit.Style.width := '64px';
      Edit.Style.padding := '6px';
      Edit.Text := '30';
    end);
  AddButton(R, 'Read it from the list', True).OnClick := procedure (Sender: TObject)
    begin
      ReadFromList;
    end;
  AddButton(R, 'Start again', False).OnClick := procedure (Sender: TObject)
    begin
      NewFibonacciList;
    end;

  Cols := Row(C);
  Cols.Style.alignItems := 'flex-start';
  Cols.Style.columnGap := '20px';
  B := Block(Cols, '1 1 360px');
  FListStatus := TQTXPanel.Create(B, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
    end);
  B := Block(Cols, '1 1 360px');
  Section(B, 'Requests so far');
  FHistory := TQTXListBox.Create(B, procedure (Box: TQTXListBox)
    begin
      Box.PositionMode := cpStatic;
      Box.Style.width := '100%';
      Box.Style.height := '170px';
      Box.Style.border := '1px solid #dde4ec';
      Box.Style.borderRadius := '4px';
      Box.Style.backgroundColor := '#ffffff';
    end);

  CompareRecursion;
  NewLazyValues;
  NewFibonacciList;
end;

{ 1. Recursion }

function StatRow(const Name, A, B: String): String;
begin
  Result := '<tr style="border-top:1px solid #dde4ec">' +
    '<td style="padding:6px 18px 6px 0;color:#555">' + Name + '</td>' +
    '<td style="padding:6px 18px;text-align:right;font-variant-numeric:tabular-nums">' + A + '</td>' +
    '<td style="padding:6px 0 6px 18px;text-align:right;font-variant-numeric:tabular-nums">' + B + '</td></tr>';
end;

procedure Tform1.CompareRecursion;
var
  Kind: TProblemKind;
  N, Index: Integer;
  Naive, Memo: TRecursionStats;
  NaiveAnswer, NaiveCalls, NaiveTime, Verdict: String;
begin
  Index := FProblem.SelectedIndex;
  if Index < 0 then
    Index := 0;
  Kind := TProblemKind(Index);
  N := EditValue(FN, 20, 0, TMemoModel.MaxN(Kind));

  Naive := TMemoModel.RunNaive(Kind, N);
  Memo := TMemoModel.RunMemoised(Kind, N);

  if Naive.Aborted then
  begin
    NaiveAnswer := '&ndash;';
    NaiveCalls := 'over ' + Thousands(NaiveCallBudget);
    NaiveTime := 'stopped';
    Verdict := 'The naive version was stopped after ' + Thousands(NaiveCallBudget) +
      ' calls - its work roughly doubles each time n goes up by one. The memoised version ' +
      'needed ' + Thousands(Memo.Calls) + '.';
  end
  else
  begin
    NaiveAnswer := Thousands(TVariant.AsFloat(Naive.Answer));
    NaiveCalls := Thousands(Naive.Calls);
    NaiveTime := FloatToStr(Round(Naive.TimeMs)) + ' ms';
    if Memo.Calls > 0 then
      Verdict := 'Same answer with ' + Thousands(Naive.Calls / Memo.Calls) +
        ' times fewer calls. Try increasing n by a few at a time.';
  end;

  FProblemNote.InnerHtml := '<div style="color:#555;font-size:13px;line-height:1.5">' +
    TMemoModel.ProblemNote(Kind) + '</div>';

  FCompare.InnerHtml :=
    '<table style="border-collapse:collapse;font-size:14px;min-width:460px">' +
    '<tr style="color:' + Muted + ';font-size:12px"><td></td>' +
    '<td style="padding:0 18px 4px;text-align:right">Naive</td>' +
    '<td style="padding:0 0 4px 18px;text-align:right">Memoised</td></tr>' +
    StatRow('Answer for ' + TMemoModel.KeyText(Kind, TMemoModel.StartKey(Kind, N)),
      NaiveAnswer, Thousands(TVariant.AsFloat(Memo.Answer))) +
    StatRow('Calls made', NaiveCalls, Thousands(Memo.Calls)) +
    StatRow('Answers taken from the cache', '0', Thousands(Memo.Hits)) +
    StatRow('Cache entries', '0', Thousands(Memo.Entries)) +
    StatRow('Deepest recursion', IntToStr(Naive.MaxDepth), IntToStr(Memo.MaxDepth)) +
    StatRow('Time', NaiveTime, FloatToStr(Round(Memo.TimeMs)) + ' ms') +
    '</table>' +
    '<p style="margin:10px 0 0 0;font-size:14px;color:#1e2a3a">' + Verdict + '</p>';

  FNaiveTree.Text := Naive.TreeText;
  FMemoTree.Text := Memo.TreeText;
end;

{ 2. Lazy values }

procedure Tform1.NewLazyValues;
var
  Thunk: TVarThunk;
begin
  Thunk := function: Variant
    begin
      Result := TMemoModel.CountPrimes(PrimeLimit);
    end;
  FCached := TLazyValue.Create(Thunk, True);
  FUncached := TLazyValue.Create(Thunk, False);
  FCachedLast := 'not read yet';
  FUncachedLast := 'not read yet';
  ShowLazyStatus;
end;

procedure Tform1.ReadLazy(Cached: Boolean);
var
  Started, Took: Float;
  Value: Variant;
  Text: String;
begin
  Started := Now;
  if Cached then
    Value := FCached.Value
  else
    Value := FUncached.Value;
  Took := (Now - Started) * 86400000;
  Text := Thousands(TVariant.AsFloat(Value)) + ' primes, read in ' + FloatToStr(Round(Took)) + ' ms';
  if Cached then
    FCachedLast := Text
  else
    FUncachedLast := Text;
  ShowLazyStatus;
end;

procedure Tform1.ShowLazyStatus;

  function Column(const Title, Colour: String; Evaluations: Integer;
    const Last, Note: String): String;
  begin
    Result := '<div style="flex:1 1 300px;border:1px solid #dde4ec;border-left:4px solid ' +
      Colour + ';border-radius:4px;padding:12px 14px;background:#ffffff">' +
      '<div style="font-weight:bold;margin-bottom:6px">' + Title + '</div>' +
      '<div style="font-size:30px;font-weight:300;font-variant-numeric:tabular-nums">' +
      IntToStr(Evaluations) + '</div>' +
      '<div style="color:' + Muted + ';font-size:12px;margin-bottom:8px">times computed</div>' +
      '<div style="font-size:13px">Last read: ' + Last + '</div>' +
      '<div style="font-size:12px;color:#555;margin-top:6px">' + Note + '</div></div>';
  end;

begin
  FLazyStatus.InnerHtml := '<div style="display:flex;flex-wrap:wrap;column-gap:16px;row-gap:12px">' +
    Column('Cached - TLazyValue.Create(Thunk, True)', Accent, FCached.EvaluationCount,
      FCachedLast, 'After the first read, every read is instant.') +
    Column('Uncached - TLazyValue.Create(Thunk, False)', Warm, FUncached.EvaluationCount,
      FUncachedLast, 'Every read pays for the whole computation again.') +
    '</div>';
end;

{ 3. Memoised infinite list }

procedure Tform1.NewFibonacciList;
begin
  FFibs := TMemoModel.FibonacciList;
  FTotalForced := 0;
  FHistory.Clear;
  FListStatus.InnerHtml := '<div style="color:#555;font-size:14px;margin-top:8px">A fresh list: ' +
    'only its first cell exists. Nothing else has been computed yet.</div>';
end;

procedure Tform1.ReadFromList;
var
  K, Before, Forced: Integer;
  Value: Variant;
  Line: String;
begin
  K := EditValue(FIndex, 30, 0, 75);
  Before := TLazyList.ForcedTails;
  Value := FFibs.Nth(K);
  Forced := TLazyList.ForcedTails - Before;
  FTotalForced := FTotalForced + Forced;

  Line := 'fib(' + IntToStr(K) + ') = ' + Thousands(TVariant.AsFloat(Value)) + '  -  ' +
    IntToStr(Forced) + ' new cells';
  FHistory.AddText(Line);

  FListStatus.InnerHtml :=
    '<div style="font-size:13px;color:' + Muted + '">fib(' + IntToStr(K) + ')</div>' +
    '<div style="font-size:30px;font-weight:300;font-variant-numeric:tabular-nums;margin-bottom:10px">' +
      Thousands(TVariant.AsFloat(Value)) + '</div>' +
    '<table style="border-collapse:collapse;font-size:14px">' +
    StatRow('New cells computed for this request', IntToStr(Forced), '') +
    StatRow('Cells computed since the list was created', IntToStr(FTotalForced), '') +
    '</table>' +
    '<p style="font-size:13px;color:#555;line-height:1.5;margin:10px 0 0 0;max-width:460px">' +
    'Computing fib(30) naively takes over 2.6 million calls. Here each cell is built once, so ' +
    'reaching term k never costs more than k cells - and cells already built are free.</p>';
end;

procedure Tform1.StyleObject;
begin
  inherited;
end;

procedure Tform1.FormPresented;
begin
  inherited;
end;

procedure Tform1.FormHidden;
begin
  inherited;
end;


end.
