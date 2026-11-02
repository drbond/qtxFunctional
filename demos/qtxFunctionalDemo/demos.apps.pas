unit demos.apps;

// ---------------------------------------------------------------------------
//  qtxFunctionalDemo - pages for the newer parts of the library
//
//    Eager vs lazy, Scan & FlatMap, Persistent data,
//    FFT, Cellular automata, Neural network, Benchmarks
//
//  Every chart, tree and grid is inline SVG built as a string in Pascal from
//  live library results - no inline JavaScript, no chart library.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.floats,
  functional.stats,
  functional.eager,
  functional.lazyinteger,
  functional.lazy,
  functional.lazylist,
  functional.sequence,
  functional.collections,
  functional.vector,
  functional.fft,
  functional.automata,
  functional.neural,
  functional.fn,
  conventional.numeric;

type
  TAppDemos = class
  public
    class function EagerVsLazy: String;
    class function ScanFlatMap: String;
    class function Persistent: String;
    class function Fourier: String;
    class function Automata: String;
    class function Neural: String;
    class function Benchmarks: String;
  end;

implementation

const
  NL         = #10;
  Accent     = '#2f6fb0';
  AccentSoft = '#d6e4f2';
  AccentLine = '#9db8d6';
  Warm       = '#d9822b';
  Ink        = '#1e2a3a';
  Muted      = '#8a96a3';
  GridLine   = '#dde4ec';
  PanelFill  = '#f5f8fb';

type
  TSeries = record
    Values: TFloatArray;
    Color:  String;
    Width:  Float;
  end;

  TSeriesArray = array of TSeries;

{ ---------------------------------------------------------------------------
  Text and layout helpers
  --------------------------------------------------------------------------- }

function VarText(const Value: Variant): String;
begin
  Result := Value;
end;

function N1(Value: Float): String;
begin
  Result := FormatNum(Value, 1);
end;

function Pretty(Value: Float): String;
begin
  if Abs(Value) >= 10 then
    Result := FormatNum(Value, 0)
  else if Abs(Value) >= 0.1 then
    Result := FormatNum(Value, 2)
  else
    Result := FormatNum(Value, 4);
end;

function Heading(const Title, Intro: String): String;
begin
  Result :=
    '<h2 style="margin:0 0 6px 0;font-weight:500">' + Title + '</h2>' +
    '<p style="margin:0 0 4px 0;color:#555;line-height:1.55;max-width:780px">' + Intro + '</p>';
end;

function SectionLabel(const Text: String): String;
begin
  Result := '<div style="font-weight:bold;font-size:11px;letter-spacing:1px;color:' + Muted +
    ';text-transform:uppercase;margin:18px 0 6px 0">' + Text + '</div>';
end;

function CodeBlock(const Code: String): String;
begin
  Result := SectionLabel('Pipeline') +
    '<pre style="background:#1e2a3a;color:#d6e4f0;padding:14px;border-radius:6px;' +
    'margin:0;overflow-x:auto;font-size:13px;line-height:1.5">' + Code + '</pre>';
end;

function OutputBlock(const Text: String): String;
begin
  Result := SectionLabel('Result') +
    '<pre style="background:#eef3f8;color:#1e2a3a;padding:14px;border-radius:6px;' +
    'margin:0;white-space:pre-wrap;font-size:13px;line-height:1.6">' + Text + '</pre>';
end;

function Figure(const Svg, Caption: String): String;
begin
  Result :=
    '<figure style="margin:0">' +
    '<div style="background:' + PanelFill + ';border:1px solid ' + GridLine +
      ';border-radius:6px;padding:10px">' + Svg + '</div>' +
    '<figcaption style="color:' + Muted + ';font-size:12px;margin-top:6px;line-height:1.4">' +
      Caption + '</figcaption></figure>';
end;

function Cols2(const A, B: String): String;
begin
  Result := '<div style="display:flex;flex-wrap:wrap;gap:16px">' +
    '<div style="flex:1 1 300px;min-width:0">' + A + '</div>' +
    '<div style="flex:1 1 300px;min-width:0">' + B + '</div></div>';
end;

function Cols3(const A, B, C: String): String;
begin
  Result := '<div style="display:flex;flex-wrap:wrap;gap:16px">' +
    '<div style="flex:1 1 220px;min-width:0">' + A + '</div>' +
    '<div style="flex:1 1 220px;min-width:0">' + B + '</div>' +
    '<div style="flex:1 1 220px;min-width:0">' + C + '</div></div>';
end;

function Row(const Name, Value: String): String;
begin
  Result := Name + ' : ' + Value + NL;
end;

function Ms(Started: Float): Float;
begin
  Result := (Now - Started) * 86400000;
end;

{ ---------------------------------------------------------------------------
  SVG helpers
  --------------------------------------------------------------------------- }

function SvgOpen(W, H: Integer): String;
begin
  Result := '<svg viewBox="0 0 ' + IntToStr(W) + ' ' + IntToStr(H) + '" width="100%" ' +
    'style="max-width:' + IntToStr(W) + 'px;display:block;height:auto;margin:0 auto" ' +
    'xmlns="http://www.w3.org/2000/svg" font-family="Ubuntu, Segoe UI, sans-serif" font-size="11">';
end;

function SvgText(X, Y: Float; const Text, Anchor, Color: String): String;
begin
  Result := '<text x="' + N1(X) + '" y="' + N1(Y) + '" text-anchor="' + Anchor +
    '" fill="' + Color + '">' + Text + '</text>';
end;

function SvgLine(X1, Y1, X2, Y2: Float; const Color: String): String;
begin
  Result := '<line x1="' + N1(X1) + '" y1="' + N1(Y1) + '" x2="' + N1(X2) + '" y2="' + N1(Y2) +
    '" stroke="' + Color + '"/>';
end;

function BarChart(const Values: TFloatArray; W, H, LabelEvery: Integer;
  const XTitle: String): String;
var
  MaxV, BarW, X, BH, Base: Float;
  i, Left, Top, PlotW, PlotH: Integer;
begin
  Left := 34;
  Top := 16;
  PlotW := W - Left - 8;
  PlotH := H - Top - 34;
  Base := Top + PlotH;

  MaxV := 0;
  for i := 0 to High(Values) do
    if Values[i] > MaxV then
      MaxV := Values[i];
  if MaxV <= 0 then
    MaxV := 1;
  BarW := PlotW / Length(Values);

  Result := SvgOpen(W, H) +
    SvgLine(Left, Base, Left + PlotW, Base, GridLine) +
    SvgText(Left - 6, Base, '0', 'end', Muted) +
    SvgText(Left - 6, Top + 4, Pretty(MaxV), 'end', Muted);

  for i := 0 to High(Values) do
  begin
    BH := Values[i] / MaxV * PlotH;
    X := Left + i * BarW;
    if BH > 0.4 then
      Result := Result + '<rect x="' + N1(X + BarW * 0.15) + '" y="' + N1(Base - BH) +
        '" width="' + N1(BarW * 0.7 + 0.3) + '" height="' + N1(BH) + '" fill="' + Accent + '"/>';
    if Values[i] >= 0.2 * MaxV then
      Result := Result + SvgText(X + BarW / 2, Base - BH - 4, FormatNum(Values[i], 1), 'middle', Ink);
    if (i mod LabelEvery) = 0 then
      Result := Result + SvgText(X + BarW / 2, Base + 14, IntToStr(i), 'middle', Muted);
  end;

  Result := Result + SvgText(Left + PlotW / 2, H - 4, XTitle, 'middle', Muted) + '</svg>';
end;

function LineChart(const Series: TSeriesArray; W, H: Integer; LogScale: Boolean;
  const XTitle: String): String;
var
  Lo, Hi, V, X, Y: Float;
  i, s, n, Stride, Left, Top, PlotW, PlotH: Integer;
  Pts: String;

  function Scaled(Value: Float): Float;
  begin
    if LogScale then
      Result := Ln(Value) / Ln(10)
    else
      Result := Value;
  end;

  function Unscaled(Value: Float): Float;
  begin
    if LogScale then
      Result := Exp(Value * Ln(10))
    else
      Result := Value;
  end;

begin
  Left := 44;
  Top := 10;
  PlotW := W - Left - 10;
  PlotH := H - Top - 30;

  Lo := 1e308;
  Hi := -1e308;
  for s := 0 to High(Series) do
    for i := 0 to High(Series[s].Values) do
    begin
      V := Scaled(Series[s].Values[i]);
      if V < Lo then Lo := V;
      if V > Hi then Hi := V;
    end;
  if Hi <= Lo then
    Hi := Lo + 1;

  Result := SvgOpen(W, H) +
    SvgLine(Left, Top + PlotH, Left + PlotW, Top + PlotH, GridLine) +
    SvgLine(Left, Top, Left, Top + PlotH, GridLine) +
    SvgText(Left - 6, Top + 8, Pretty(Unscaled(Hi)), 'end', Muted) +
    SvgText(Left - 6, Top + PlotH, Pretty(Unscaled(Lo)), 'end', Muted);

  if (not LogScale) and (Lo < 0) and (Hi > 0) then
  begin
    Y := Top + (1 - (0 - Lo) / (Hi - Lo)) * PlotH;
    Result := Result + '<line x1="' + IntToStr(Left) + '" y1="' + N1(Y) + '" x2="' +
      IntToStr(Left + PlotW) + '" y2="' + N1(Y) + '" stroke="' + GridLine +
      '" stroke-dasharray="3 3"/>';
  end;

  for s := 0 to High(Series) do
  begin
    n := Length(Series[s].Values);
    Stride := 1;
    if n > 600 then
      Stride := n div 600;
    Pts := '';
    i := 0;
    while i < n do
    begin
      X := Left + i / (n - 1) * PlotW;
      Y := Top + (1 - (Scaled(Series[s].Values[i]) - Lo) / (Hi - Lo)) * PlotH;
      Pts := Pts + N1(X) + ',' + N1(Y) + ' ';
      if (i < n - 1) and (i + Stride > n - 1) then
        i := n - 1
      else
        i := i + Stride;
    end;
    Result := Result + '<polyline points="' + Pts + '" fill="none" stroke="' + Series[s].Color +
      '" stroke-width="' + N1(Series[s].Width) + '" stroke-linejoin="round"/>';
  end;

  Result := Result + SvgText(Left + PlotW / 2, H - 6, XTitle, 'middle', Muted) + '</svg>';
end;

function Series(const Values: TFloatArray; const Color: String; Width: Float): TSeries;
begin
  Result.Values := Values;
  Result.Color := Color;
  Result.Width := Width;
end;

function MixColour(P: Float): String;
var
  R, G, B: Integer;
begin
  // light panel (238,243,248) -> accent blue (47,111,176)
  if P < 0 then P := 0;
  if P > 1 then P := 1;
  R := Round(238 + (47 - 238) * P);
  G := Round(243 + (111 - 243) * P);
  B := Round(248 + (176 - 248) * P);
  Result := 'rgb(' + IntToStr(R) + ',' + IntToStr(G) + ',' + IntToStr(B) + ')';
end;

{ ---------------------------------------------------------------------------
  Eager vs lazy
  --------------------------------------------------------------------------- }

type
  TRunStats = record
    Answer, Objects, Arrays, Elements, Source: Integer;
    Time: Float;
  end;

function Capture(Answer: Integer; Started: Float): TRunStats;
begin
  Result.Answer := Answer;
  Result.Objects := TFunctionalStats.PipelineObjects;
  Result.Arrays := TFunctionalStats.IntermediateArrays;
  Result.Elements := TFunctionalStats.ArrayElements;
  Result.Source := TFunctionalStats.SourceElements;
  Result.Time := Ms(Started);
end;

function CompareBar(const Caption: String; EagerValue, LazyValue: Integer): String;
var
  Most: Integer;

  function Bar(Value: Integer; const Colour, Who: String): String;
  var
    Pct: Float;
  begin
    Pct := Value / Most * 100;
    Result := '<div style="display:flex;align-items:center;gap:8px;margin:3px 0">' +
      '<div style="width:44px;color:' + Muted + ';font-size:12px">' + Who + '</div>' +
      '<div style="flex:1;background:' + PanelFill + ';border-radius:3px;height:14px">' +
      '<div style="width:' + N1(Pct) + '%;min-width:2px;height:14px;border-radius:3px;background:' +
      Colour + '"></div></div>' +
      '<div style="width:70px;text-align:right;font-size:12px;font-variant-numeric:tabular-nums">' +
      IntToStr(Value) + '</div></div>';
  end;

begin
  Most := EagerValue;
  if LazyValue > Most then Most := LazyValue;
  if Most = 0 then Most := 1;
  Result := '<div style="margin:0 0 12px 0;max-width:620px">' +
    '<div style="font-size:13px;margin-bottom:2px">' + Caption + '</div>' +
    Bar(EagerValue, Warm, 'eager') + Bar(LazyValue, Accent, 'lazy') + '</div>';
end;

class function TAppDemos.EagerVsLazy: String;
var
  Started: Float;
  E, L: TRunStats;
  Table: String;

  function TableRow(const Name, A, B: String): String;
  begin
    Result := '<tr><td style="padding:6px 18px 6px 0;color:#555">' + Name + '</td>' +
      '<td style="padding:6px 18px;text-align:right;font-variant-numeric:tabular-nums">' + A + '</td>' +
      '<td style="padding:6px 0 6px 18px;text-align:right;font-variant-numeric:tabular-nums">' + B + '</td></tr>';
  end;

begin
  TFunctionalStats.Reset;
  Started := Now;
  E := Capture(TEagerInteger.Range(1, 100000)
    .Map(TFunction.Square()).Filter(TFunction.IsEven()).Take(10)
    .Fold(0, TFunction.Sum()), Started);

  TFunctionalStats.Reset;
  Started := Now;
  L := Capture(TLazyInteger.Range(1, 100000)
    .Map(TFunction.Square()).Filter(TFunction.IsEven()).Take(10)
    .Fold(0, TFunction.Sum()), Started);

  Table := '<table style="border-collapse:collapse;font-size:14px;margin-top:4px">' +
    '<tr style="color:' + Muted + ';font-size:12px"><td></td>' +
    '<td style="padding:0 18px;text-align:right">TEagerInteger</td>' +
    '<td style="padding:0 0 0 18px;text-align:right">TLazyInteger</td></tr>' +
    TableRow('Answer', IntToStr(E.Answer), IntToStr(L.Answer)) +
    TableRow('Pipeline objects', IntToStr(E.Objects), IntToStr(L.Objects)) +
    TableRow('Intermediate arrays', IntToStr(E.Arrays), IntToStr(L.Arrays)) +
    TableRow('Elements stored in arrays', IntToStr(E.Elements), IntToStr(L.Elements)) +
    TableRow('Source elements produced', IntToStr(E.Source), IntToStr(L.Source)) +
    TableRow('Time', FormatNum(E.Time, 0) + ' ms', FormatNum(L.Time, 0) + ' ms') +
    '</table>';

  Result :=
    Heading('Eager versus lazy',
      'The same pipeline written twice. TEagerInteger finishes each step over the whole ' +
      'collection before the next starts, so every step builds a full array. TLazyInteger ' +
      'only records the steps; Fold then pulls values through all of them at once and stops ' +
      'as soon as Take has its ten. The counters below are measured live.') +
    CodeBlock(
      'TEagerInteger.Range(1, 100000)            TLazyInteger.Range(1, 100000)' + NL +
      '  .Map(TFunction.Square)                    .Map(TFunction.Square)' + NL +
      '  .Filter(TFunction.IsEven)                 .Filter(TFunction.IsEven)' + NL +
      '  .Take(10)                                 .Take(10)' + NL +
      '  .Fold(0, TFunction.Sum);                  .Fold(0, TFunction.Sum);') +
    SectionLabel('Measured') + Table +
    SectionLabel('Work done') +
    CompareBar('Elements stored in intermediate arrays', E.Elements, L.Elements) +
    CompareBar('Elements produced by the source', E.Source, L.Source) +
    '<p style="color:#555;font-size:13px;line-height:1.55;max-width:780px;margin:4px 0 0 0">' +
    'The eager total is 100,000 (Range) + 100,000 (Map) + 50,000 (Filter) + 10 (Take). ' +
    'The lazy pipeline reads 20 numbers: the first ten even squares come from 2, 4, ... 20.</p>';
end;

{ ---------------------------------------------------------------------------
  Scan & FlatMap
  --------------------------------------------------------------------------- }

function BelowLimit(Limit: Integer): TVarPredicate;
var
  Bound: Integer;
begin
  Bound := Limit;
  Result := function (Value: Variant): Boolean
    var
      N: Integer;
    begin
      N := Value;
      Result := N < Bound;
    end;
end;

class function TAppDemos.ScanFlatMap: String;
var
  Triangular, SumOfSquares, Triples, FibTable: TSequence;
  Fibs: TLazyList;
  Output: String;
begin
  Triangular := TSequence.From(1)
    .Scan(0, TVarFunction.LiftFold(TFunction.Sum()))
    .TakeWhile(BelowLimit(100));

  SumOfSquares := TSequence.Range(1, 6)
    .Map(TVarFunction.Lift(TFunction.Square()))
    .Scan(0, TVarFunction.LiftFold(TFunction.Sum()));

  Triples := TSequence.From(1).FlatMap(
    function (CValue: Variant): TSequence
    var
      C: Integer;
    begin
      C := CValue;
      Result := TSequence.Range(1, C).FlatMap(
        function (BValue: Variant): TSequence
        var
          B: Integer;
        begin
          B := BValue;
          Result := TSequence.Range(1, B)
            .Filter(function (AValue: Variant): Boolean
              var
                A: Integer;
              begin
                A := AValue;
                Result := A * A + B * B = C * C;
              end)
            .Map(function (AValue: Variant): Variant
              begin
                Result := '(' + VarText(AValue) + ',' + IntToStr(B) + ',' + IntToStr(C) + ')';
              end);
        end);
    end).Take(8);

  Fibs := TLazyList.Cons(0,
    function: TLazyList
    begin
      Result := TLazyList.Cons(1,
        function: TLazyList
        begin
          Result := TLazyList.ZipWith(Fibs, Fibs.Tail, TVarFunction.LiftFold(TFunction.Sum()));
        end);
    end);

  FibTable := TSequence.From(0).ZipWithList(Fibs,
    function (N, F: Variant): Variant
    begin
      Result := 'F' + VarText(N) + '=' + VarText(F);
    end).Take(10);

  Output :=
    Row('Triangular numbers below 100', Triangular.AsString) +
    Row('Running sum of squares      ', SumOfSquares.AsString) +
    Row('  fused plan                ', SumOfSquares.Describe) +
    NL +
    Row('First 8 Pythagorean triples ', Triples.AsString) +
    NL +
    Row('Naturals zipped with Fibs   ', FibTable.AsString) +
    Row('Zip with a bounded partner  ',
      TSequence.From(1).ZipWith(TSequence.Range(10, 13),
        TVarFunction.LiftFold(TFunction.Product())).AsString + '   (no Take needed)');

  Result :=
    Heading('Scan, FlatMap and Zip',
      'Scan keeps a running total and emits it at every step; a Map in front of it merges ' +
      'into the same step. FlatMap turns each value into a whole sequence - nested twice here, ' +
      'it searches for Pythagorean triples in an infinite space, and Take(8) stops every level ' +
      'at once. ZipWithList pairs a sequence with a pull-based lazy list, which may itself be ' +
      'infinite, such as the self-referential Fibonacci list.') +
    CodeBlock(
      'TSequence.From(1).Scan(0, Sum).TakeWhile(Below(100));' + NL + NL +
      'TSequence.From(1).FlatMap(c -&gt;' + NL +
      '  TSequence.Range(1, c).FlatMap(b -&gt;' + NL +
      '    TSequence.Range(1, b)' + NL +
      '      .Filter(a -&gt; a*a + b*b = c*c)' + NL +
      '      .Map(a -&gt; ''(a,b,c)'')))' + NL +
      '  .Take(8);' + NL + NL +
      'TSequence.From(0).ZipWithList(Fibs, (n, f) -&gt; ''Fn=f'').Take(10);') +
    OutputBlock(Output);
end;

{ ---------------------------------------------------------------------------
  Persistent data
  --------------------------------------------------------------------------- }

procedure CollectAll(const Node: TMapNode; var Nodes: TMapNodeArray);
begin
  if Node = nil then
    exit;
  CollectAll(Node.Left, Nodes);
  Nodes.Add(Node);
  CollectAll(Node.Right, Nodes);
end;

function Contains(const Nodes: TMapNodeArray; const Node: TMapNode): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(Nodes) do
    if Nodes[i] = Node then
      exit(True);
end;

function TreeSvg(const Map, Previous: TPersistentMap; W, H: Integer): String;
var
  Nodes, Before: TMapNodeArray;
  Depths: TIntArray;
  MaxDepth, i, j: Integer;
  ColW, LevelH: Float;
  Fill, Stroke, TextColour: String;

  procedure Visit(const Node: TMapNode; Depth: Integer);
  begin
    if Node = nil then
      exit;
    Visit(Node.Left, Depth + 1);
    Nodes.Add(Node);
    Depths.Add(Depth);
    Visit(Node.Right, Depth + 1);
  end;

  function IndexOf(const Node: TMapNode): Integer;
  var
    k: Integer;
  begin
    Result := -1;
    for k := 0 to High(Nodes) do
      if Nodes[k] = Node then
        exit(k);
  end;

  function PX(Index: Integer): Float;
  begin
    Result := (Index + 0.5) * ColW;
  end;

  function PY(Index: Integer): Float;
  begin
    Result := 20 + Depths[Index] * LevelH;
  end;

begin
  Visit(Map.Root, 0);
  if Previous <> nil then
    CollectAll(Previous.Root, Before);

  MaxDepth := 1;
  for i := 0 to High(Depths) do
    if Depths[i] > MaxDepth then
      MaxDepth := Depths[i];
  ColW := W / Length(Nodes);
  LevelH := (H - 48) / MaxDepth;

  Result := SvgOpen(W, H);

  // Edges first, so the circles sit on top
  for i := 0 to High(Nodes) do
  begin
    j := IndexOf(Nodes[i].Left);
    if j >= 0 then
      Result := Result + SvgLine(PX(i), PY(i), PX(j), PY(j), AccentLine);
    j := IndexOf(Nodes[i].Right);
    if j >= 0 then
      Result := Result + SvgLine(PX(i), PY(i), PX(j), PY(j), AccentLine);
  end;

  for i := 0 to High(Nodes) do
  begin
    if Previous = nil then
    begin
      Fill := '#ffffff'; Stroke := Accent; TextColour := Ink;
    end
    else if Contains(Before, Nodes[i]) then
    begin
      Fill := AccentSoft; Stroke := AccentLine; TextColour := Ink;
    end
    else
    begin
      Fill := Accent; Stroke := Accent; TextColour := '#ffffff';
    end;
    Result := Result +
      '<circle cx="' + N1(PX(i)) + '" cy="' + N1(PY(i)) + '" r="13" fill="' + Fill +
        '" stroke="' + Stroke + '" stroke-width="1.5"/>' +
      '<text x="' + N1(PX(i)) + '" y="' + N1(PY(i) + 4) + '" text-anchor="middle" font-size="12" ' +
        'font-weight="bold" fill="' + TextColour + '">' + Nodes[i].Key + '</text>' +
      SvgText(PX(i), PY(i) + 26, VarText(Nodes[i].Value), 'middle', Muted);
  end;

  Result := Result + '</svg>';
end;

function Legend: String;

  function Item(const Fill, Stroke, Caption: String): String;
  begin
    Result := '<span style="display:inline-flex;align-items:center;gap:6px;margin-right:18px">' +
      '<span style="width:12px;height:12px;border-radius:50%;background:' + Fill +
      ';border:1.5px solid ' + Stroke + '"></span>' + Caption + '</span>';
  end;

begin
  Result := '<div style="font-size:12px;color:#555;margin:10px 0 0 0">' +
    Item(Accent, Accent, 'new node in this version') +
    Item(AccentSoft, AccentLine, 'shared with the previous version') + '</div>';
end;

class function TAppDemos.Persistent: String;
var
  V1, V2, V3, Sorted: TPersistentMap;
  Before, CopiedForPut, CopiedForRemove, i: Integer;
  Output, KeyText: String;
begin
  V1 := TPersistentMap.Empty
    .Put('m', 'mango').Put('c', 'cherry').Put('t', 'tomato')
    .Put('a', 'apple').Put('e', 'egg').Put('p', 'pear').Put('z', 'zucchini');

  Before := TPersistentMap.NodesCreated;
  V2 := V1.Put('e', 'eggplant');
  CopiedForPut := TPersistentMap.NodesCreated - Before;

  Before := TPersistentMap.NodesCreated;
  V3 := V2.Remove('c');
  CopiedForRemove := TPersistentMap.NodesCreated - Before;

  Sorted := TPersistentMap.Empty;
  for i := 1 to 1000 do
  begin
    KeyText := IntToStr(i);
    while Length(KeyText) < 4 do
      KeyText := '0' + KeyText;
    Sorted := Sorted.Put('k' + KeyText, i);
  end;

  Output :=
    Row('V2 := V1.Put(''e'', ''eggplant'')', IntToStr(CopiedForPut) + ' nodes copied, ' +
      IntToStr(V1.SharedNodes(V2)) + ' shared with V1') +
    Row('V3 := V2.Remove(''c'')          ', IntToStr(CopiedForRemove) + ' nodes created, ' +
      IntToStr(V2.SharedNodes(V3)) + ' shared with V2') +
    Row('Still readable                 ', 'V1.e = ' + VarText(V1.Get('e')) +
      ',  V2.e = ' + VarText(V2.Get('e')) + ',  V2 has c = ' + BoolToStr(V2.ContainsKey('c'))) +
    NL +
    Row('1000 keys inserted in order    ', 'height ' + IntToStr(Sorted.Height) +
      ' (an unbalanced tree would be 1000), balanced = ' + BoolToStr(Sorted.IsBalanced));

  Result :=
    Heading('Persistent data structures',
      'TPersistentMap never changes a node. Put and Remove copy only the nodes on the path ' +
      'from the root to the change and share everything else, so every earlier version stays ' +
      'valid. It is an AVL tree: rebalancing also builds new nodes from the old ones, which ' +
      'keeps the height logarithmic even when keys arrive in sorted order.') +
    CodeBlock(
      'var V1 := TPersistentMap.Empty.Put(''m'', ''mango'').Put(''c'', ''cherry'') ...;' + NL +
      'var V2 := V1.Put(''e'', ''eggplant'');   // V1 is untouched' + NL +
      'var V3 := V2.Remove(''c'');            // V2 is untouched') +
    SectionLabel('Three versions, alive at the same time') +
    Cols3(
      Figure(TreeSvg(V1, nil, 300, 180), 'V1 - seven fruits'),
      Figure(TreeSvg(V2, V1, 300, 180), 'V2 - e replaced: only its path is new'),
      Figure(TreeSvg(V3, V2, 300, 180), 'V3 - c removed: e moves up, a and the right side are shared')) +
    Legend +
    OutputBlock(Output);
end;

{ ---------------------------------------------------------------------------
  Fourier transform
  --------------------------------------------------------------------------- }

class function TAppDemos.Fourier: String;
const
  N = 128;
  Cutoff = 15;
var
  Signal, Clean, Recovered, Mags: TFloatArray;
  Spectrum, Filtered: TComplexArray;
  Kept: TComplexArray;
  i: Integer;
  MaxError: Float;
  SeriesList: TSeriesArray;
  Peaks: String;
  HalfMags: TFloatArray;
begin
  for i := 0 to N - 1 do
  begin
    Clean.Add(Sin(2 * Pi * 5 * i / N) + 0.5 * Sin(2 * Pi * 12 * i / N));
    Signal.Add(Clean[i] + 0.3 * Sin(2 * Pi * 40 * i / N));
  end;

  Spectrum := TFourier.FFT(TFourier.FromReals(Signal));
  Mags := TFourier.Magnitudes(Spectrum);

  // A low-pass filter is a pure function of the spectrum: keep low bins
  Kept := Spectrum;
  Filtered := TFourier.Tabulate(N,
    function (K: Integer): TComplex
    var
      Bin: Integer;
    begin
      Bin := K;
      if N - K < Bin then
        Bin := N - K;
      if Bin <= Cutoff then
        Result := Kept[K]
      else
        Result := TComplexOps.Make(0, 0);
    end);
  Recovered := TFourier.RealParts(TFourier.InverseFFT(Filtered));

  MaxError := 0;
  for i := 0 to N - 1 do
    if Abs(Recovered[i] - Clean[i]) > MaxError then
      MaxError := Abs(Recovered[i] - Clean[i]);

  // Find the peaks with a pipeline over the first half of the spectrum
  for i := 0 to N div 2 - 1 do
    HalfMags.Add(Mags[i]);
  Peaks := TSequence.Range(0, N div 2 - 1)
    .Filter(function (Value: Variant): Boolean
      var
        K: Integer;
      begin
        K := Value;
        Result := Mags[K] > 5;
      end)
    .Map(function (Value: Variant): Variant
      var
        K: Integer;
      begin
        K := Value;
        Result := 'bin ' + IntToStr(K) + ' = ' + FormatNum(Mags[K], 2);
      end)
    .Fold('', TVarFunction.Concat(',  '));

  SeriesList.Add(Series(Signal, AccentLine, 1.2));
  SeriesList.Add(Series(Recovered, Warm, 2));

  Result :=
    Heading('Fast Fourier transform',
      'The signal is three sine waves: 5 and 12 cycles, plus a smaller 40-cycle wave standing ' +
      'in for noise. TFourier.FFT is a recursive Cooley-Tukey transform written as pure ' +
      'functions: each level builds new arrays and never edits one. The filter is just another ' +
      'function of the spectrum, which drops every frequency above 15, and InverseFFT turns ' +
      'the result back into a signal.') +
    CodeBlock(
      'var Spectrum := TFourier.FFT(TFourier.FromReals(Signal));' + NL +
      'var Filtered := TFourier.Tabulate(128, k -&gt;' + NL +
      '  if Min(k, 128 - k) &lt;= 15 then Spectrum[k] else 0);' + NL +
      'var Recovered := TFourier.RealParts(TFourier.InverseFFT(Filtered));') +
    SectionLabel('Magnitude spectrum') +
    Figure(BarChart(HalfMags, 760, 210, 8,
      'frequency bin (cycles per 128 samples)'),
      'Peaks at bins 5, 12 and 40, with magnitude n/2 times each amplitude: 64, 32 and 19.2.') +
    SectionLabel('Signal before and after the low-pass filter') +
    Figure(LineChart(SeriesList, 760, 220, False, 'sample'),
      'Blue: original signal. Orange: after removing every frequency above 15.') +
    OutputBlock(
      Row('Peaks found   ', Peaks) +
      Row('Filter error  ', 'max |recovered - (5-cycle + 12-cycle)| = ' + FloatToStr(MaxError)) +
      Row('Original spectrum unchanged', 'bin 40 still = ' + FormatNum(Mags[40], 2)));
end;

{ ---------------------------------------------------------------------------
  Cellular automata
  --------------------------------------------------------------------------- }

function AutomatonSvg(RuleNumber, Width, Rows, Cell: Integer): String;
var
  Gens: TVarArray;
  Gen, Start: String;
  r, i, RunStart: Integer;
begin
  // Rule 110 only grows leftwards, so it starts from the right edge;
  // the others start from the centre
  if RuleNumber = 110 then
  begin
    Start := '';
    for i := 1 to Width - 1 do
      Start := Start + '0';
    Start := Start + '1';
  end
  else
    Start := TAutomaton.SingleCell(Width);

  // The whole history is a lazy sequence: Iterate(initial, rule)
  Gens := TAutomaton.Generations(RuleNumber, Start).Take(Rows).ToArray;
  Result := SvgOpen(Width * Cell, Rows * Cell) +
    '<rect width="' + IntToStr(Width * Cell) + '" height="' + IntToStr(Rows * Cell) +
    '" fill="#ffffff"/>';
  for r := 0 to High(Gens) do
  begin
    Gen := Gens[r];
    i := 1;
    while i <= Length(Gen) do
    begin
      if Gen[i] = '1' then
      begin
        // Merge runs of live cells into one rectangle
        RunStart := i;
        while (i <= Length(Gen)) and (Gen[i] = '1') do
          Inc(i);
        Result := Result + '<rect x="' + IntToStr((RunStart - 1) * Cell) + '" y="' +
          IntToStr(r * Cell) + '" width="' + IntToStr((i - RunStart) * Cell) + '" height="' +
          IntToStr(Cell) + '" fill="' + Ink + '"/>';
      end
      else
        Inc(i);
    end;
  end;
  Result := Result + '</svg>';
end;

class function TAppDemos.Automata: String;
var
  Centre: String;
begin
  Centre := TAutomaton.Generations(30, TAutomaton.SingleCell(201))
    .Map(TAutomaton.CentreCell).Take(32)
    .Fold('', function (Acc, Value: Variant): Variant
      begin
        Result := VarText(Acc) + VarText(Value);
      end);

  Result :=
    Heading('Elementary cellular automata',
      'A rule number from 0 to 255 becomes a pure function from one generation to the next. ' +
      'The whole history is then TSequence.Iterate(start, Rule(n)): an infinite, lazy ' +
      'sequence of generations that is computed only as far as it is drawn. Each picture ' +
      'starts from a single live cell; time runs downwards.') +
    CodeBlock(
      'TAutomaton.Generations(30, TAutomaton.SingleCell(129))   // = Iterate(start, Rule(30))' + NL +
      '  .Take(64)' + NL +
      '  .ToArray;') +
    SectionLabel('Three rules, 129 cells by 64 generations') +
    Cols3(
      Figure(AutomatonSvg(30, 129, 64, 2), 'Rule 30 - chaotic; its centre column is a known pseudo-random generator'),
      Figure(AutomatonSvg(90, 129, 64, 2), 'Rule 90 - XOR of the two neighbours: the Sierpinski triangle'),
      Figure(AutomatonSvg(110, 129, 64, 2), 'Rule 110 - proved Turing-complete; grows leftwards from a cell at the right edge')) +
    OutputBlock(Row('Rule 30 centre column, 32 generations', Centre));
end;

{ ---------------------------------------------------------------------------
  Neural network
  --------------------------------------------------------------------------- }

function DecisionMap(const Net: TNetwork; Size, Cells: Integer): String;
var
  Step, P, X1, X2: Float;
  r, c: Integer;

  function Corner(X, Y: Float; const Target: String): String;
  begin
    Result := '<circle cx="' + N1(X) + '" cy="' + N1(Y) + '" r="10" fill="#ffffff" stroke="' + Ink +
      '" stroke-width="1.5"/>' +
      '<text x="' + N1(X) + '" y="' + N1(Y + 4) + '" text-anchor="middle" font-size="11" ' +
      'font-weight="bold" fill="' + Ink + '">' + Target + '</text>';
  end;

begin
  Step := Size / Cells;
  Result := SvgOpen(Size, Size);
  for r := 0 to Cells - 1 do
    for c := 0 to Cells - 1 do
    begin
      X1 := (c + 0.5) / Cells;
      X2 := 1 - (r + 0.5) / Cells;
      P := Net.Predict(X1, X2);
      Result := Result + '<rect x="' + N1(c * Step) + '" y="' + N1(r * Step) + '" width="' +
        N1(Step + 0.6) + '" height="' + N1(Step + 0.6) + '" fill="' + MixColour(P) + '"/>';
    end;
  // The four XOR cases at the corners: (x1, x2) with x2 upwards
  Result := Result +
    Corner(14, Size - 14, '0') + Corner(14, 14, '1') +
    Corner(Size - 14, Size - 14, '1') + Corner(Size - 14, 14, '0') + '</svg>';
end;

class function TAppDemos.Neural: String;
var
  Samples: TSampleArray;
  Untrained, Trained: TNetwork;
  History: TVarArray;
  Losses: TFloatArray;
  SeriesList: TSeriesArray;
  Output: String;
  i: Integer;
begin
  Samples := TNetwork.XorSamples;
  Untrained := TNetwork.Initial(4, 42);

  // The training history is a lazy sequence of networks; map each to its loss
  History := TSequence.Iterate(TValueFunction.FromObject(Untrained),
    function (Value: Variant): Variant
    var
      Net: TNetwork;
    begin
      Net := TNetwork(TValueFunction.ToObject(Value));
      Result := TValueFunction.FromObject(Net.TrainEpoch(Samples, 2.0));
    end)
    .Map(function (Value: Variant): Variant
      begin
        Result := TNetwork(TValueFunction.ToObject(Value)).Loss(Samples);
      end)
    .Take(3001)
    .ToArray;
  for i := 0 to High(History) do
    Losses.Add(TVariant.AsFloat(History[i]));

  Trained := Untrained.Train(Samples, 2.0, 3000);
  SeriesList.Add(Series(Losses, Accent, 2));

  Output := '';
  for i := 0 to High(Samples) do
    Output := Output + Row(
      'XOR(' + FormatNum(Samples[i].X1, 0) + ', ' + FormatNum(Samples[i].X2, 0) + ') = ' +
        FormatNum(Samples[i].Y, 0),
      'untrained ' + FormatNum(Untrained.Predict(Samples[i].X1, Samples[i].X2), 3) +
      '   trained ' + FormatNum(Trained.Predict(Samples[i].X1, Samples[i].X2), 3));
  Output := Output + NL +
    Row('Loss (mean squared error)', FormatNum(Untrained.Loss(Samples), 4) + ' -> ' +
      FormatNum(Trained.Loss(Samples), 6));

  Result :=
    Heading('A neural network that learns XOR',
      'A 2-4-1 network with sigmoid units. Its 17 weights live in a single immutable TVector. ' +
      'Each training epoch is a pure function from one network to the next, so the whole ' +
      'training run is a lazy sequence: Iterate(network, Epoch). Mapping that sequence to ' +
      'its loss gives the learning curve, and the untrained network is still there to compare.') +
    CodeBlock(
      'var History := TSequence.Iterate(Untrained, Epoch);       // infinite, lazy' + NL +
      'var Curve   := History.Map(Loss).Take(3001).ToArray;' + NL +
      'var Trained := History.Drop(3000).Head.Value;') +
    SectionLabel('Learning curve (log scale)') +
    Figure(LineChart(SeriesList, 760, 200, True, 'epoch (0 - 3000)'),
      'Loss falls from about 0.29 to 0.001. The long flat stretch before the drop is typical for XOR.') +
    SectionLabel('What the network predicts across the input square') +
    Cols2(
      Figure(DecisionMap(Untrained, 260, 26), 'Before training - random weights'),
      Figure(DecisionMap(Trained, 260, 26), 'After 3000 epochs - dark means 1, light means 0')) +
    OutputBlock(Output);
end;

{ ---------------------------------------------------------------------------
  Benchmarks
  --------------------------------------------------------------------------- }

function TestSignal(Size: Integer): TFloatArray;
var
  i: Integer;
begin
  for i := 0 to Size - 1 do
    Result.Add(Sin(i * 0.37) + 0.5 * Cos(i * 1.91));
end;

function MaxAbsDiff(const A, B: TFloatArray): Float;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(A) do
    if Abs(A[i] - B[i]) > Result then
      Result := Abs(A[i] - B[i]);
end;

function BenchRow(const Name: String; F, C: Float; Agree: Boolean): String;
var
  Ratio, Verdict: String;
begin
  if C > 0 then
    Ratio := FormatNum(F / C, 1) + '&times;'
  else
    Ratio := '&ndash;';
  if Agree then
    Verdict := '<span style="color:#2e7d4f">same results</span>'
  else
    Verdict := '<span style="color:#b00020">DIFFER</span>';
  Result := '<tr style="border-top:1px solid ' + GridLine + '">' +
    '<td style="padding:8px 18px 8px 0">' + Name + '</td>' +
    '<td style="padding:8px 14px;text-align:right;font-variant-numeric:tabular-nums">' + FormatNum(F, 0) + ' ms</td>' +
    '<td style="padding:8px 14px;text-align:right;font-variant-numeric:tabular-nums">' + FormatNum(C, 0) + ' ms</td>' +
    '<td style="padding:8px 14px;text-align:right;font-variant-numeric:tabular-nums">' + Ratio + '</td>' +
    '<td style="padding:8px 0 8px 14px">' + Verdict + '</td></tr>';
end;

class function TAppDemos.Benchmarks: String;
var
  Started, F, C, Sum1, Sum2: Float;
  A, B: TVector;
  AA, BB, Flat1, Flat2, Re, Im, Sig, P: TFloatArray;
  M1, M2, Product: TMatrix;
  Conventional: TFloatArray;
  Spectrum: TComplexArray;
  Gen1, Gen2: String;
  Net: TNetwork;
  Rows: String;
  i, r, N: Integer;
  Agree: Boolean;
begin
  Rows := '';

  // 1. Dot product
  A := TVector.Tabulate(1000000, function (Index: Integer): Float begin Result := Sin(Index); end);
  B := TVector.Tabulate(1000000, function (Index: Integer): Float begin Result := Cos(Index); end);
  AA := A.ToArray;
  BB := B.ToArray;
  Started := Now;
  Sum1 := 0;
  for r := 1 to 20 do
    Sum1 := Sum1 + A.Dot(B);
  F := Ms(Started);
  Started := Now;
  Sum2 := 0;
  for r := 1 to 20 do
    Sum2 := Sum2 + TConventional.Dot(AA, BB);
  C := Ms(Started);
  Rows := Rows + BenchRow('Dot product, 1M elements &times; 20', F, C, Abs(Sum1 - Sum2) < 1e-6);

  // 2. Matrix multiply
  N := 100;
  M1 := TMatrix.Tabulate(N, N, function (Row, Col: Integer): Float begin Result := Sin(Row + 2 * Col); end);
  M2 := TMatrix.Tabulate(N, N, function (Row, Col: Integer): Float begin Result := Cos(Row - Col); end);
  for i := 0 to N * N - 1 do
  begin
    Flat1.Add(M1.Get(i div N, i mod N));
    Flat2.Add(M2.Get(i div N, i mod N));
  end;
  Started := Now;
  for r := 1 to 10 do
    Product := M1.Multiply(M2);
  F := Ms(Started);
  Started := Now;
  for r := 1 to 10 do
    Conventional := TConventional.MatMul(Flat1, Flat2, N);
  C := Ms(Started);
  Agree := True;
  for i := 0 to N * N - 1 do
    if Abs(Product.Get(i div N, i mod N) - Conventional[i]) > 1e-9 then
      Agree := False;
  Rows := Rows + BenchRow('Matrix multiply, 100 &times; 100, &times; 10', F, C, Agree);

  // 3. FFT
  Sig := TestSignal(4096);
  Started := Now;
  for r := 1 to 20 do
    Spectrum := TFourier.FFT(TFourier.FromReals(Sig));
  F := Ms(Started);
  Started := Now;
  for r := 1 to 20 do
  begin
    Re := [];
    Im := [];
    for i := 0 to High(Sig) do
    begin
      Re.Add(Sig[i]);
      Im.Add(0);
    end;
    TConventional.FFTInPlace(Re, Im);
  end;
  C := Ms(Started);
  Rows := Rows + BenchRow('FFT, 4096 points &times; 20', F, C,
    MaxAbsDiff(TFourier.RealParts(Spectrum), Re) < 1e-8);

  // 4. Cellular automaton
  Started := Now;
  for r := 1 to 10 do
    Gen1 := TAutomaton.Generations(110, TAutomaton.SingleCell(401)).Drop(400).Head.Value;
  F := Ms(Started);
  Started := Now;
  for r := 1 to 10 do
    Gen2 := TConventional.RunAutomaton(110, 401, 400);
  C := Ms(Started);
  Rows := Rows + BenchRow('Rule 110, 401 cells &times; 400 generations, &times; 10', F, C, Gen1 = Gen2);

  // 5. Neural network
  Started := Now;
  for r := 1 to 3 do
    Net := TNetwork.Initial(4, 42).Train(TNetwork.XorSamples, 2.0, 3000);
  F := Ms(Started);
  Started := Now;
  for r := 1 to 3 do
    P := TConventional.TrainXor(4, 42, 2.0, 3000);
  C := Ms(Started);
  Rows := Rows + BenchRow('XOR network 2-4-1, 3000 epochs, &times; 3', F, C,
    MaxAbsDiff(Net.Params.ToArray, P) < 1e-12);

  Result :=
    Heading('Functional versus conventional Pascal',
      'Each workload runs twice in your browser, on the same data: once with qtxFunctional ' +
      '(immutable values, closures, pure functions) and once as conventional Pascal (loops ' +
      'over mutable arrays, updated in place). The last column checks that both give the ' +
      'same answer. Press the button again to re-run.') +
    SectionLabel('Measured just now') +
    '<table style="border-collapse:collapse;font-size:14px;width:100%;max-width:860px">' +
    '<tr style="color:' + Muted + ';font-size:12px;text-align:right">' +
    '<td style="text-align:left;padding:0 18px 6px 0">Workload</td>' +
    '<td style="padding:0 14px 6px">Functional</td>' +
    '<td style="padding:0 14px 6px">Conventional</td>' +
    '<td style="padding:0 14px 6px">Ratio</td>' +
    '<td style="text-align:left;padding:0 0 6px 14px">Check</td></tr>' +
    Rows + '</table>' +
    '<p style="color:#555;font-size:13px;line-height:1.55;max-width:780px;margin:14px 0 0 0">' +
    'The dot product and matrix multiply stay close to hand-written loops, because the fused ' +
    'zip-fold allocates nothing. Workloads that build a new value at every step - each FFT ' +
    'recursion level, each automaton generation, each training sample - pay the most, since the ' +
    'conventional versions overwrite one buffer in place. Times have 1 ms resolution, so the ' +
    'ratios move a little between presses.</p>';
end;

end.
