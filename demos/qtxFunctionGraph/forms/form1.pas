unit form1;

// ---------------------------------------------------------------------------
//  qtxFunctionGraph - main form
//
//  Standard Quartex controls only: TQTXComboBox, TQTXCheckbox, TQTXButton,
//  TQTXListBox, TQTXMemo and TQTXPanel. The engine is functional.graph.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  qtx.classes,
  qtx.components,
  qtx.time,
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
  qtx.dom.control.checkbox,
  qtx.dom.control.listbox,
  qtx.dom.control.memo,
  functional.graph,
  graph.scenarios,
  graph.view;

type
  TRuleBoxes = array of TQTXCheckbox;

  Tform1 = class( TQTXForm )
  {$I "intf::form1"}
  private
    FScenario:    TQTXComboBox;
    FDescription: TQTXPanel;
    FRules:       TRuleBoxes;
    FBeforeView:  TQTXPanel;
    FAfterView:   TQTXPanel;
    FLog:         TQTXMemo;
    FResults:     TQTXPanel;
    FBeforeText:  TQTXMemo;
    FAfterText:   TQTXMemo;

    function  Section(const Parent: TQTXComponent; const Caption: String): TQTXPanel;
    function  Row(const Parent: TQTXComponent): TQTXPanel;
    function  Block(const Parent: TQTXComponent; const Flex: String): TQTXPanel;
    function  Frame(const Parent: TQTXComponent): TQTXPanel;
    function  AddButton(const Parent: TQTXComponent; const Caption: String;
      Primary: Boolean): TQTXButton;
    function  TextMemo(const Parent: TQTXComponent): TQTXMemo;
    function  SelectedRules: TOptimiserRules;

    procedure RunScenario;
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

function Tform1.Row(const Parent: TQTXComponent): TQTXPanel;
begin
  Result := TQTXPanel.Create(TQTXDOMComponent(Parent), procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdFlex;
      Panel.Style.flexWrap := 'wrap';
      Panel.Style.alignItems := 'flex-start';
      Panel.Style.columnGap := '20px';
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

function Tform1.Frame(const Parent: TQTXComponent): TQTXPanel;
begin
  Result := TQTXPanel.Create(TQTXDOMComponent(Parent), procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.backgroundColor := '#f5f8fb';
      Panel.Style.border := '1px solid #dde4ec';
      Panel.Style.borderRadius := '6px';
      Panel.Style.padding := '10px';
      Panel.Style.overflowX := 'auto';
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
      Button.Style.marginTop := '12px';
      if IsPrimary then
      begin
        Button.Style.backgroundColor := Accent;
        Button.Style.borderColor := Accent;
        Button.Style.color := '#ffffff';
      end;
    end);
end;

function Tform1.TextMemo(const Parent: TQTXComponent): TQTXMemo;
begin
  Result := TQTXMemo.Create(TQTXDOMComponent(Parent), procedure (Memo: TQTXMemo)
    begin
      Memo.PositionMode := cpStatic;
      Memo.ReadOnly := True;
      Memo.Style.width := '100%';
      Memo.Style.height := '170px';
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

function Tform1.SelectedRules: TOptimiserRules;
var
  r: TOptimiserRule;
begin
  Result := [];
  for r := Low(TOptimiserRule) to High(TOptimiserRule) do
    if FRules[Ord(r)].Checked then
      Include(Result, r);
end;

{ Building the UI }

procedure Tform1.BuildUI;
var
  Main, Left, Right, Cols, B: TQTXPanel;
  i: Integer;
  r: TOptimiserRule;
  Box: TQTXCheckbox;
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
        '<h1 style="margin:0;font-weight:500;font-size:28px">qtx<b>FunctionGraph</b></h1>' +
        '<div style="color:#555;margin-top:6px;line-height:1.55;max-width:960px">' +
        'Rather than running functions straight away, the program first builds a graph that ' +
        'describes the computation. Because the graph is an ordinary immutable value it can be ' +
        'inspected, rewritten by an optimiser into a cheaper equivalent, and only then executed ' +
        '- every output in a single pass over the source.</div>';
    end);

  Main := TQTXPanel.Create(Self, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdFlex;
      Panel.Style.flexWrap := 'wrap';
      Panel.Style.columnGap := '32px';
      Panel.Style.marginTop := '6px';
    end);
  Left := Block(Main, '0 0 340px');
  Right := Block(Main, '1 1 560px');

  { Left: choices }

  Section(Left, '1. Graph');
  FScenario := TQTXComboBox.Create(Left, procedure (Combo: TQTXComboBox)
    begin
      Combo.PositionMode := cpStatic;
      Combo.Style.width := '100%';
      Combo.Style.padding := '6px';
    end);
  for i := 0 to ScenarioCount - 1 do
    FScenario.Add(TScenarios.Title(i));
  FDescription := TQTXPanel.Create(Left, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.marginTop := '8px';
    end);

  Section(Left, '2. Optimiser rules');
  for r := Low(TOptimiserRule) to High(TOptimiserRule) do
  begin
    Box := TQTXCheckbox.Create(Left, procedure (Check: TQTXCheckbox)
      begin
        Check.PositionMode := cpStatic;
        Check.DisplayMode := cdBlock;
        Check.Style.width := '100%';
        Check.Style.height := '26px';
        Check.Style.position := 'relative';
      end);
    Box.Caption := TFunctionGraph.RuleTitle(r);
    Box.Checked := True;
    Box.OnChecked := procedure (Sender: TObject; const Value: Boolean)
      begin
        // The event fires before the browser has toggled the box,
        // so re-run once the click has finished
        TQTXDispatch.Execute(procedure ()
          begin
            RunScenario;
          end, 10);
      end;
    FRules.Add(Box);
  end;

  AddButton(Left, 'Build, optimise and run', True).OnClick := procedure (Sender: TObject)
    begin
      RunScenario;
    end;

  Section(Left, '3. What the optimiser did');
  FLog := TQTXMemo.Create(Left, procedure (Memo: TQTXMemo)
    begin
      Memo.PositionMode := cpStatic;
      Memo.ReadOnly := True;
      Memo.Style.width := '100%';
      Memo.Style.height := '230px';
      Memo.Style.padding := '10px';
      Memo.Style.border := '1px solid #dde4ec';
      Memo.Style.borderRadius := '4px';
      Memo.Style.boxSizing := 'border-box';
      Memo.Style.fontFamily := 'Ubuntu, "Segoe UI", Roboto, sans-serif';
      Memo.Style.fontSize := '13px';
      Memo.Style.lineHeight := '1.45';
      Memo.Style.whiteSpace := 'pre-wrap';
    end);

  { Right: graphs and results }

  Cols := Row(Right);
  B := Block(Cols, '1 1 300px');
  Section(B, 'As written');
  FBeforeView := Frame(B);
  B := Block(Cols, '1 1 300px');
  Section(B, 'After the optimiser (new nodes outlined in bold)');
  FAfterView := Frame(B);

  Section(Right, 'Results');
  FResults := TQTXPanel.Create(Right, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
    end);

  Cols := Row(Right);
  B := Block(Cols, '1 1 300px');
  Section(B, 'Graph as text - as written');
  FBeforeText := TextMemo(B);
  B := Block(Cols, '1 1 300px');
  Section(B, 'Graph as text - optimised');
  FAfterText := TextMemo(B);

  RunScenario;
end;

{ Running }

function Cell(const Text: String; Right: Boolean): String;
begin
  if Right then
    Result := '<td style="padding:6px 14px;text-align:right;font-variant-numeric:tabular-nums">' +
      Text + '</td>'
  else
    Result := '<td style="padding:6px 14px 6px 0;color:#555">' + Text + '</td>';
end;

function ResultRow(const Name, A, B, C: String): String;
begin
  Result := '<tr style="border-top:1px solid #dde4ec">' + Cell(Name, False) +
    Cell(A, True) + Cell(B, True) + Cell(C, True) + '</tr>';
end;

procedure Tform1.RunScenario;
var
  Index, i: Integer;
  Graph, Optimised: TFunctionGraph;
  Log: TTextList;
  Written, Fast, Separate: TGraphRun;
  Html: String;
  Same: Boolean;
  LogText: String;
begin
  Index := FScenario.SelectedIndex;
  if Index < 0 then
    Index := 0;

  FDescription.InnerHtml := '<div style="color:#555;font-size:13px;line-height:1.5">' +
    TScenarios.Description(Index) + '</div>';

  // Build - nothing runs yet
  Graph := TScenarios.Build(Index);

  // Inspect and optimise - still nothing runs
  Log := [];
  Optimised := Graph.Optimise(SelectedRules, Log);

  FBeforeView.InnerHtml := GraphSvg(Graph, nil);
  FAfterView.InnerHtml := GraphSvg(Optimised, Graph);
  FBeforeText.Text := Graph.ToText;
  FAfterText.Text := Optimised.ToText;

  LogText := '';
  for i := 0 to High(Log) do
    LogText := LogText + IntToStr(i + 1) + '.  ' + Log[i] + #10#10;
  FLog.Text := LogText;

  // Execute three ways
  Written := Graph.Execute;
  Fast := Optimised.Execute;
  Separate := Graph.ExecuteSeparately;

  if Written.Error <> '' then
  begin
    FResults.InnerHtml := '<div style="background:#fdecee;color:#b00020;padding:12px 14px;' +
      'border-radius:6px;font-size:14px;line-height:1.5;max-width:760px"><b>Not executed:</b> ' +
      Written.Error + '.<br>The engine checked the graph before running it - ' +
      'add a Take after the source, or choose a finite source.</div>';
    exit;
  end;

  Html := '<table style="border-collapse:collapse;font-size:14px;width:100%;max-width:900px">' +
    '<tr style="color:' + Muted + ';font-size:12px;text-align:right">' +
    '<td style="text-align:left;padding:0 14px 6px 0"></td>' +
    '<td style="padding:0 14px 6px">Graph as written<br>one pass</td>' +
    '<td style="padding:0 14px 6px">Optimised graph<br>one pass</td>' +
    '<td style="padding:0 14px 6px">Each output<br>run on its own</td></tr>';

  Same := True;
  for i := 0 to High(Written.Names) do
  begin
    Html := Html + ResultRow('Output "' + Written.Names[i] + '"', Written.AsText(i),
      Fast.AsText(i), Separate.AsText(i));
    if (Written.AsText(i) <> Fast.AsText(i)) or (Written.AsText(i) <> Separate.AsText(i)) then
      Same := False;
  end;

  Html := Html +
    ResultRow('Nodes', IntToStr(Graph.NodeCount), IntToStr(Optimised.NodeCount), '&ndash;') +
    ResultRow('Elements read from the source', IntToStr(Written.SourcePulls),
      IntToStr(Fast.SourcePulls), IntToStr(Separate.SourcePulls)) +
    ResultRow('Steps run (Map, Filter, Scan and Fold calls)', IntToStr(Written.Calls),
      IntToStr(Fast.Calls), IntToStr(Separate.Calls)) +
    '</table>';

  if Same then
    Html := Html + '<p style="color:#2e7d4f;font-size:14px;margin:10px 0 0 0">' +
      'All three ways give the same results.</p>'
  else
    Html := Html + '<p style="color:#b00020;font-size:14px;margin:10px 0 0 0">' +
      'The results differ - this would be an optimiser bug.</p>';

  Html := Html + '<p style="color:#555;font-size:13px;line-height:1.5;max-width:900px;margin:6px 0 0 0">' +
    'A fused node still runs every function it was made from, but as one step with no ' +
    'hand-off between nodes. Sharing duplicate work removes real calls, and a single pass ' +
    'reads each source element once, however many outputs use it.</p>';

  FResults.InnerHtml := Html;
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
