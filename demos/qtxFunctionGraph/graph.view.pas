unit graph.view;

// ---------------------------------------------------------------------------
//  qtxFunctionGraph - drawing a graph as inline SVG
//
//  Every node has one input, so each source is the root of a tree. Leaves
//  get consecutive columns; a parent sits above the middle of its children.
//  Nodes created by the optimiser are outlined in bold. Built as a string in
//  Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.graph;

function GraphSvg(const Graph, Previous: TFunctionGraph): String;

implementation

const
  Ink    = '#1e2a3a';
  Muted  = '#8a96a3';
  Edge   = '#9db8d6';
  BoxW   = 168;
  BoxH   = 40;
  ColW   = 186;
  RowH   = 86;
  Top    = 14;

type
  TFloats = array of Float;
  TInts   = array of Integer;

function N1(Value: Float): String;
begin
  Result := FloatToStr(Round(Value * 10) / 10);
end;

function Escape(const S: String): String;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    case S[i] of
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '&': Result := Result + '&amp;';
      '"': Result := Result + '&quot;';
    else
      Result := Result + S[i];
    end;
end;

function Fit(const S: String; MaxChars: Integer): String;
begin
  if Length(S) <= MaxChars then
    Result := S
  else
    Result := Copy(S, 1, MaxChars - 1) + '...';
end;

procedure KindColours(Kind: TGraphKind; var Fill, Stroke: String);
begin
  case Kind of
    gkSource:         begin Fill := '#1e2a3a'; Stroke := '#1e2a3a'; end;
    gkMap:            begin Fill := '#e4eef8'; Stroke := '#2f6fb0'; end;
    gkFilter:         begin Fill := '#fbefe3'; Stroke := '#d9822b'; end;
    gkTake, gkDrop:   begin Fill := '#eef0f2'; Stroke := '#8a96a3'; end;
    gkScan, gkFold:   begin Fill := '#e5f3ea'; Stroke := '#2e7d4f'; end;
  end;
end;

function GraphSvg(const Graph, Previous: TFunctionGraph): String;
var
  All, Before: TGraphNodes;
  X, Y: TFloats;
  Depth: TInts;
  NextLeaf: Float;
  MaxDepth, i, k: Integer;
  W, H, CX, CY, Extra: Float;
  Fill, Stroke, TextColour, Width: String;
  Outs: TTextList;
  IsNew: Boolean;

  function IndexOf(const Node: TGraphNode): Integer;
  var
    j: Integer;
  begin
    Result := -1;
    for j := 0 to High(All) do
      if All[j] = Node then
        exit(j);
  end;

  function SameWorkIn(const List: TGraphNodes; const Node: TGraphNode): Boolean;
  var
    j: Integer;
  begin
    Result := False;
    for j := 0 to High(List) do
      if (List[j] = Node) or ((List[j].Kind = Node.Kind) and (List[j].Name = Node.Name)) then
        exit(True);
  end;

  // Place a node and its subtree; returns the node's x position
  function Place(Index, D: Integer): Float;
  var
    j, Kids: Integer;
    Sum: Float;
  begin
    Depth[Index] := D;
    if D > MaxDepth then
      MaxDepth := D;
    Kids := 0;
    Sum := 0;
    for j := 0 to High(All) do
      if All[j].Input = All[Index] then
      begin
        Sum := Sum + Place(j, D + 1);
        Inc(Kids);
      end;
    if Kids = 0 then
    begin
      Result := NextLeaf;
      NextLeaf := NextLeaf + 1;
    end
    else
      Result := Sum / Kids;
    X[Index] := Result;
  end;

begin
  All := Graph.Nodes;
  if Previous <> nil then
    Before := Previous.Nodes;

  for i := 0 to High(All) do
  begin
    X.Add(0);
    Y.Add(0);
    Depth.Add(0);
  end;

  NextLeaf := 0;
  MaxDepth := 0;
  for i := 0 to High(All) do
    if All[i].Kind = gkSource then
      Place(i, 0);

  W := NextLeaf * ColW;
  if W < ColW then
    W := ColW;
  H := Top + (MaxDepth + 1) * RowH + 8;

  Result := '<svg viewBox="0 0 ' + N1(W) + ' ' + N1(H) + '" width="100%" ' +
    'style="max-width:' + N1(W) + 'px;display:block;height:auto;margin:0 auto" ' +
    'xmlns="http://www.w3.org/2000/svg" font-family="Ubuntu, Segoe UI, sans-serif" font-size="11">' +
    '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" ' +
    'markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="' +
    Edge + '"/></marker></defs>';

  // Edges
  for i := 0 to High(All) do
    if All[i].Input <> nil then
    begin
      k := IndexOf(All[i].Input);
      Result := Result + '<line x1="' + N1(X[k] * ColW + ColW / 2) + '" y1="' +
        N1(Top + Depth[k] * RowH + BoxH) + '" x2="' + N1(X[i] * ColW + ColW / 2) + '" y2="' +
        N1(Top + Depth[i] * RowH - 2) + '" stroke="' + Edge + '" stroke-width="1.5" ' +
        'marker-end="url(#arrow)"/>';
    end;

  // Nodes
  for i := 0 to High(All) do
  begin
    CX := X[i] * ColW + ColW / 2;
    CY := Top + Depth[i] * RowH;
    KindColours(All[i].Kind, Fill, Stroke);
    if All[i].Kind = gkSource then
      TextColour := '#ffffff'
    else
      TextColour := Ink;
    // "New" means made by a rewrite: a node copied only because its input
    // changed does the same work, so it is matched by content, not identity
    IsNew := (Previous <> nil) and not SameWorkIn(Before, All[i]);
    if IsNew then
      Width := '3'
    else
      Width := '1.5';

    Result := Result +
      '<rect x="' + N1(CX - BoxW / 2) + '" y="' + N1(CY) + '" width="' + IntToStr(BoxW) +
        '" height="' + IntToStr(BoxH) + '" rx="6" fill="' + Fill + '" stroke="' + Stroke +
        '" stroke-width="' + Width + '"/>' +
      '<text x="' + N1(CX - BoxW / 2 + 8) + '" y="' + N1(CY + 15) + '" font-size="10" ' +
        'font-weight="bold" fill="' + TextColour + '">' + All[i].KindText + '</text>' +
      '<text x="' + N1(CX + BoxW / 2 - 8) + '" y="' + N1(CY + 15) + '" font-size="10" ' +
        'text-anchor="end" fill="' + TextColour + '" opacity="0.7">' + All[i].Tag + '</text>' +
      '<text x="' + N1(CX - BoxW / 2 + 8) + '" y="' + N1(CY + 31) + '" font-size="12" fill="' +
        TextColour + '">' + Escape(Fit(All[i].Name, 24)) + '</text>';

    // Output labels under the node
    Outs := Graph.OutputsOf(All[i]);
    Extra := 0;
    for k := 0 to High(Outs) do
    begin
      Result := Result + '<text x="' + N1(CX) + '" y="' + N1(CY + BoxH + 14 + Extra) +
        '" text-anchor="middle" font-size="11" font-weight="bold" fill="#2f6fb0">=&gt; ' +
        Escape(Outs[k]) + '</text>';
      Extra := Extra + 13;
    end;
  end;

  Result := Result + '</svg>';
end;

end.
