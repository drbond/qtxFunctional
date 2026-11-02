unit form1;

// ---------------------------------------------------------------------------
//  qtxLazySequence - main form
//
//  Standard Quartex controls only: TQTXComboBox, TQTXNumberEdit, TQTXButton,
//  TQTXListBox, TQTXMemo and TQTXPanel. All logic lives in lazyseq.model.
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
  lazyseq.model;

type

  Tform1 = class( TQTXForm )
  {$I "intf::form1"}
  private
    FSource:   TQTXComboBox;
    FStage:    TQTXComboBox;
    FParam:    TQTXNumberEdit;
    FStages:   TQTXListBox;
    FExamples: TQTXComboBox;
    FSummary:  TQTXPanel;
    FTrace:    TQTXMemo;
    FSpecs:    TStageSpecs;

    function  Section(const Parent: TQTXComponent; const Caption: String): TQTXPanel;
    function  Column(const Parent: TQTXComponent; const Width: String): TQTXPanel;
    function  Row(const Parent: TQTXComponent): TQTXPanel;
    function  AddButton(const Parent: TQTXComponent; const Caption: String;
      Primary: Boolean): TQTXButton;
    function  ParamValue: Integer;

    procedure AddStage;
    procedure RemoveLastStage;
    procedure ClearStages;
    procedure LoadExample(Index: Integer);
    procedure RefreshStageList;
    procedure RunPipeline;
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
  Muted  = '#8a96a3';
  Accent = '#2f6fb0';

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

function Tform1.Section(const Parent: TQTXComponent; const Caption: String): TQTXPanel;
begin
  Result := TQTXPanel.Create(TQTXDOMComponent(Parent), procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.margin := '16px 0 6px 0';
      Panel.InnerHtml := '<span style="font-size:11px;font-weight:bold;letter-spacing:1px;' +
        'text-transform:uppercase;color:' + Muted + '">' + Caption + '</span>';
    end);
end;

function Tform1.Column(const Parent: TQTXComponent; const Width: String): TQTXPanel;
var
  W: String;
begin
  W := Width;
  Result := TQTXPanel.Create(TQTXDOMComponent(Parent), procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      if W = '' then
      begin
        Panel.Style.flex := '1 1 420px';
        Panel.Style.minWidth := '0';
      end
      else
      begin
        Panel.Style.flex := '0 0 ' + W;
        Panel.Style.width := W;
      end;
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
      Panel.Style.marginBottom := '8px';
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

function Tform1.ParamValue: Integer;
begin
  try
    Result := StrToInt(FParam.Text);
  except
    Result := 5;
  end;
  if Result < 0 then
    Result := 0;
  if Result > 100000 then
    Result := 100000;
end;

{ Building the UI }

procedure Tform1.BuildUI;
var
  Main, Left, Right, R: TQTXPanel;
  k: TSourceKind;
  s: TStageKind;
begin
  // Fill the browser window instead of the designer's fixed size
  Style.height := '100vh';
  Style.width := '100%';
  Style.padding := '24px 32px';
  Style.overflowY := 'auto';
  Style.fontFamily := 'Ubuntu, "Segoe UI", Roboto, sans-serif';
  Style.color := '#1e2a3a';

  TQTXPanel.Create(Self, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.InnerHtml :=
        '<h1 style="margin:0;font-weight:500;font-size:28px">qtx<b>LazySequence</b></h1>' +
        '<div style="color:#555;margin-top:6px;line-height:1.55;max-width:900px">' +
        'Choose a source, add stages, then run. Nothing is computed while you build the ' +
        'pipeline - each stage is only recorded. When it runs, every element travels through ' +
        'all the stages before the next one is produced, and the run stops as soon as a Take ' +
        'or TakeWhile is satisfied. The trace on the right shows this happening.</div>';
    end);

  Main := TQTXPanel.Create(Self, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdFlex;
      Panel.Style.flexWrap := 'wrap';
      Panel.Style.columnGap := '32px';
      Panel.Style.marginTop := '8px';
      Panel.Style.paddingBottom := '32px';
    end);

  Left := Column(Main, '340px');
  Right := Column(Main, '');

  { Left column: building the pipeline }

  Section(Left, '1. Source');
  FSource := TQTXComboBox.Create(Left, procedure (Box: TQTXComboBox)
    begin
      Box.PositionMode := cpStatic;
      Box.Style.width := '100%';
      Box.Style.padding := '6px';
    end);
  for k := Low(TSourceKind) to High(TSourceKind) do
    FSource.Add(TLazyModel.SourceTitle(k));

  Section(Left, '2. Stages');
  R := Row(Left);
  FStage := TQTXComboBox.Create(R, procedure (Box: TQTXComboBox)
    begin
      Box.PositionMode := cpStatic;
      Box.Style.flex := '1';
      Box.Style.padding := '6px';
    end);
  for s := Low(TStageKind) to High(TStageKind) do
    FStage.Add(TLazyModel.StageTitle(s));
  FParam := TQTXNumberEdit.Create(R, procedure (Edit: TQTXNumberEdit)
    begin
      Edit.PositionMode := cpStatic;
      Edit.Style.width := '64px';
      Edit.Style.padding := '6px';
      Edit.Text := '5';
    end);

  R := Row(Left);
  AddButton(R, 'Add stage', False).OnClick := procedure (Sender: TObject)
    begin
      AddStage;
    end;
  AddButton(R, 'Remove last', False).OnClick := procedure (Sender: TObject)
    begin
      RemoveLastStage;
    end;
  AddButton(R, 'Clear', False).OnClick := procedure (Sender: TObject)
    begin
      ClearStages;
    end;

  FStages := TQTXListBox.Create(Left, procedure (Box: TQTXListBox)
    begin
      Box.PositionMode := cpStatic;
      Box.Style.width := '100%';
      Box.Style.height := '190px';
      Box.Style.border := '1px solid #dde4ec';
      Box.Style.borderRadius := '4px';
      Box.Style.backgroundColor := '#ffffff';
    end);

  Section(Left, '3. Run');
  R := Row(Left);
  AddButton(R, 'Run pipeline', True).OnClick := procedure (Sender: TObject)
    begin
      RunPipeline;
    end;

  Section(Left, 'Or load an example');
  R := Row(Left);
  FExamples := TQTXComboBox.Create(R, procedure (Box: TQTXComboBox)
    begin
      Box.PositionMode := cpStatic;
      Box.Style.flex := '1';
      Box.Style.padding := '6px';
    end);
  FExamples.Add('First 5 odd squares (infinite source)');
  FExamples.Add('Powers of two below 1000');
  FExamples.Add('Running totals that are even');
  FExamples.Add('Five primes after the 25th');
  FExamples.Add('Fusion: 7 stages become 3');
  FExamples.Add('Collatz from 27: the first 25 steps');
  AddButton(R, 'Load', False).OnClick := procedure (Sender: TObject)
    begin
      LoadExample(FExamples.SelectedIndex);
    end;

  { Right column: results }

  Section(Right, 'Result');
  FSummary := TQTXPanel.Create(Right, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
    end);

  Section(Right, 'Trace - one line per function call, in the order they happen');
  FTrace := TQTXMemo.Create(Right, procedure (Memo: TQTXMemo)
    begin
      Memo.PositionMode := cpStatic;
      Memo.ReadOnly := True;
      Memo.Style.width := '100%';
      Memo.Style.height := '360px';
      Memo.Style.fontFamily := 'Consolas, "Courier New", monospace';
      Memo.Style.fontSize := '12px';
      Memo.Style.lineHeight := '1.5';
      Memo.Style.padding := '10px';
      Memo.Style.border := '1px solid #dde4ec';
      Memo.Style.borderRadius := '4px';
      Memo.Style.boxSizing := 'border-box';
    end);

  LoadExample(0);
end;

{ Stage list }

procedure Tform1.RefreshStageList;
var
  i: Integer;
begin
  FStages.Clear;
  for i := 0 to High(FSpecs) do
    FStages.AddText(IntToStr(i + 1) + '.  ' + TLazyModel.StageName(FSpecs[i]));
end;

procedure Tform1.AddStage;
var
  Kind: TStageKind;
  Index: Integer;
begin
  Index := FStage.SelectedIndex;
  if Index < 0 then
    Index := 0;
  Kind := TStageKind(Index);
  FSpecs.Add(TLazyModel.Spec(Kind, ParamValue));
  RefreshStageList;
  RunPipeline;
end;

procedure Tform1.RemoveLastStage;
begin
  if Length(FSpecs) > 0 then
    FSpecs.Delete(High(FSpecs));
  RefreshStageList;
  RunPipeline;
end;

procedure Tform1.ClearStages;
begin
  FSpecs := [];
  RefreshStageList;
  RunPipeline;
end;

procedure Tform1.LoadExample(Index: Integer);
var
  Source: TSourceKind;
begin
  FSpecs := [];
  Source := skNaturals;
  case Index of
    1:
      begin
        Source := skPowers;
        FSpecs.Add(TLazyModel.Spec(stTakeWhile, 1000));
      end;
    2:
      begin
        Source := skRange20;
        FSpecs.Add(TLazyModel.Spec(stScanSum, 0));
        FSpecs.Add(TLazyModel.Spec(stEven, 0));
      end;
    3:
      begin
        Source := skNaturals;
        FSpecs.Add(TLazyModel.Spec(stPrime, 0));
        FSpecs.Add(TLazyModel.Spec(stDrop, 25));
        FSpecs.Add(TLazyModel.Spec(stTake, 5));
      end;
    4:
      begin
        Source := skRange1000;
        // (x + 1) * 3 + 1, kept when odd and prime: three Maps, two Filters, two Takes
        FSpecs.Add(TLazyModel.Spec(stAddOne, 0));
        FSpecs.Add(TLazyModel.Spec(stTriple, 0));
        FSpecs.Add(TLazyModel.Spec(stAddOne, 0));
        FSpecs.Add(TLazyModel.Spec(stOdd, 0));
        FSpecs.Add(TLazyModel.Spec(stPrime, 0));
        FSpecs.Add(TLazyModel.Spec(stTake, 10));
        FSpecs.Add(TLazyModel.Spec(stTake, 4));
      end;
    5:
      begin
        Source := skCollatz;
        FSpecs.Add(TLazyModel.Spec(stTake, 25));
      end;
  else
    begin
      Source := skNaturals;
      FSpecs.Add(TLazyModel.Spec(stSquare, 0));
      FSpecs.Add(TLazyModel.Spec(stOdd, 0));
      FSpecs.Add(TLazyModel.Spec(stTake, 5));
    end;
  end;
  FSource.SelectedIndex := Ord(Source);
  RefreshStageList;
  RunPipeline;
end;

{ Running }

function TableRow(const Name, Lazy, Eager: String): String;
begin
  Result := '<tr style="border-top:1px solid #dde4ec">' +
    '<td style="padding:6px 18px 6px 0;color:#555">' + Name + '</td>' +
    '<td style="padding:6px 18px;text-align:right;font-variant-numeric:tabular-nums">' + Lazy + '</td>' +
    '<td style="padding:6px 0 6px 18px;text-align:right;font-variant-numeric:tabular-nums">' + Eager + '</td></tr>';
end;

procedure Tform1.RunPipeline;
var
  Report: TRunReport;
  Source: TSourceKind;
  Html, Hint, EagerPulls, EagerCalls, EagerArrays, EagerStored: String;
  Index: Integer;
begin
  Index := FSource.SelectedIndex;
  if Index < 0 then
    Index := 0;
  Source := TSourceKind(Index);
  Report := TLazyModel.Run(Source, FSpecs);

  Html := '<div style="font-size:13px;color:#555;margin-bottom:4px">Fused plan - ' +
    IntToStr(Report.WrittenStages) + ' stages written, ' + IntToStr(Report.FusedStages) +
    ' after fusion</div>' +
    '<pre style="background:#1e2a3a;color:#d6e4f0;padding:10px 12px;border-radius:6px;' +
    'margin:0 0 12px 0;white-space:pre-wrap;font-size:13px">' + Report.Plan + '</pre>';

  if Report.Error <> '' then
  begin
    if Pos('bounded', Report.Error) > 0 then
      Hint := '<br>An infinite source needs a Take or TakeWhile stage so the pipeline knows when to stop.'
    else
      Hint := '<br>The stages may never let enough values through - for example, two ' +
        'filters that no number can pass together.';
    Html := Html + '<div style="background:#fdecee;color:#b00020;padding:10px 12px;' +
      'border-radius:6px;font-size:14px;line-height:1.5"><b>Not run:</b> ' + Report.Error +
      Hint + '</div>';
  end
  else
  begin
    Html := Html + '<pre style="background:#eef3f8;padding:10px 12px;border-radius:6px;' +
      'margin:0 0 12px 0;white-space:pre-wrap;font-size:14px">' + Report.Values + '</pre>';

    if Report.EagerPossible then
    begin
      EagerPulls := IntToStr(Report.EagerPulls);
      EagerCalls := IntToStr(Report.EagerCalls);
      EagerArrays := IntToStr(Report.EagerArrays);
      EagerStored := IntToStr(Report.EagerMaterialised);
    end
    else
    begin
      EagerPulls := '&infin;';
      EagerCalls := '&infin;';
      EagerArrays := '&ndash;';
      EagerStored := '&infin;';
    end;

    Html := Html +
      '<table style="border-collapse:collapse;font-size:14px;min-width:420px">' +
      '<tr style="color:' + Muted + ';font-size:12px"><td></td>' +
      '<td style="padding:0 18px 4px;text-align:right">Lazy</td>' +
      '<td style="padding:0 0 4px 18px;text-align:right">Eager</td></tr>' +
      TableRow('Elements produced by the source', IntToStr(Report.SourcePulls), EagerPulls) +
      TableRow('Stage function calls', IntToStr(Report.Calls), EagerCalls) +
      TableRow('Whole lists built', '0', EagerArrays) +
      TableRow('Elements stored', IntToStr(Report.Delivered) + ' (result only)', EagerStored) +
      '</table>';

    if not Report.EagerPossible then
      Html := Html + '<p style="color:#555;font-size:13px;line-height:1.5;max-width:640px;' +
        'margin:10px 0 0 0">' + Report.EagerNote + '</p>'
    else if Report.EagerValues <> Report.Values then
      Html := Html + '<p style="color:#b00020">Eager result differs: ' + Report.EagerValues + '</p>';
  end;

  FSummary.InnerHtml := Html;
  FTrace.Text := Report.Trace;
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
