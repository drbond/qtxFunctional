unit functional.graph;

// ---------------------------------------------------------------------------
//  qtxFunctional - functional computation graphs (qtxFunctionGraph)
//
//  Instead of running functions straight away, a program first BUILDS a
//  graph describing the computation:
//
//      Source -> Map(F) -> Map(G) -> Filter(P) -> output
//
//  The graph is an ordinary immutable value, so it can be inspected
//  (ToText, Nodes), transformed by an optimiser that rewrites it into a
//  cheaper but equivalent graph (Optimise, with a log of every rewrite),
//  and finally executed (Execute).
//
//  Nodes have one input, but a node may feed several others, and a graph
//  may have several named outputs. Execute serves every output in ONE
//  traversal of each source: values fan out to all consumers, and the
//  source stops as soon as no branch wants more. ExecuteSeparately runs each
//  output on its own, for comparison.
//
//  Optimiser rules (each can be switched off):
//    orMapFusion      Map g . Map f           -> Map (g . f)
//    orFilterFusion   Filter q . Filter p     -> Filter (p and q)
//    orTakeDrop       Take m . Take n         -> Take (min n m)
//                     Drop m . Drop n         -> Drop (n + m)
//    orFoldFusion     Fold/Scan g . Map f     -> Fold/Scan (\a x -> g a (f x))
//    orIdentity       Map id                  -> (removed)
//    orShareWork      two identical nodes     -> one shared node (CSE)
//
//  A fusion rule only fires when the inner node has a single consumer:
//  if its result is also used elsewhere, merging would mean computing it
//  twice, so the optimiser keeps it and says so in the log.
//
//  Node identity for sharing: two nodes are the same work when they have
//  the same kind, the same name, the same parameters and the same input.
//  Names therefore stand for functions - use one name per function.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.sequence;

type
  TGraphKind = (gkSource, gkMap, gkFilter, gkTake, gkDrop, gkScan, gkFold);

  TGraphNode = class;
  TGraphNodes = array of TGraphNode;

  TGraphNode = class
  private
    FId:        Integer;
    FKind:      TGraphKind;
    FName:      String;
    FInput:     TGraphNode;
    FMapFn:     TVarFunc;
    FPredicate: TVarPredicate;
    FFoldFn:    TVarFoldFunc;
    FSeed:      Variant;
    FLimit:     Integer;
    FSource:    TSequence;
    FIdentity:  Boolean;
    class var FNextId: Integer;
    constructor CreateNode(Kind: TGraphKind; const Name: String; const Input: TGraphNode);
    function Derive(Kind: TGraphKind; const Name: String): TGraphNode;
  public
    class function Source(const Name: String; const Seq: TSequence): TGraphNode;
    class procedure ResetIds;

    function Map(const Name: String; const Fn: TVarFunc): TGraphNode;
    function Identity: TGraphNode;
    function Filter(const Name: String; const Predicate: TVarPredicate): TGraphNode;
    function Take(Count: Integer): TGraphNode;
    function Drop(Count: Integer): TGraphNode;
    function Scan(const Name: String; const Seed: Variant; const Fn: TVarFoldFunc): TGraphNode;
    function Fold(const Name: String; const Seed: Variant; const Fn: TVarFoldFunc): TGraphNode;

    function WithInput(const NewInput: TGraphNode): TGraphNode;   // copy, new id
    function Signature: String;
    function KindText: String;
    function Caption: String;
    function Tag: String;          // e.g. "n3"

    property Id: Integer read FId;
    property Kind: TGraphKind read FKind;
    property Name: String read FName;
    property Input: TGraphNode read FInput;
    property Limit: Integer read FLimit;
    property Seed: Variant read FSeed;
    property MapFn: TVarFunc read FMapFn;
    property Predicate: TVarPredicate read FPredicate;
    property FoldFn: TVarFoldFunc read FFoldFn;
    property SourceSequence: TSequence read FSource;
    property IsIdentity: Boolean read FIdentity;
  end;

  TGraphOutput = record
    Name: String;
    Node: TGraphNode;
  end;

  TGraphOutputs = array of TGraphOutput;

  TOptimiserRule = (orMapFusion, orFilterFusion, orTakeDrop, orFoldFusion,
                    orIdentity, orShareWork);
  TOptimiserRules = set of TOptimiserRule;

  TTextList = array of String;
  TItemLists = array of TVarArray;

  TGraphRun = class
  public
    Names:        TTextList;
    IsScalar:     array of Boolean;
    Values:       TVarArray;
    Items:        TItemLists;
    SourcePulls:  Integer;
    Calls:        Integer;
    Error:        String;
    function Find(const OutputName: String): Integer;
    function AsText(Index: Integer): String;
  end;

  TFunctionGraph = class
  private
    FOutputs: TGraphOutputs;
    function IndexIn(const List: TGraphNodes; const Node: TGraphNode): Integer;
    function RewritePass(Rules: TOptimiserRules; ShareOnly: Boolean;
      var Log: TTextList; var Changed: Boolean): TFunctionGraph;
    procedure CheckBounded;
  public
    constructor Create;
    class function AllRules: TOptimiserRules;
    class function RuleTitle(Rule: TOptimiserRule): String;

    function Output(const Name: String; const Node: TGraphNode): TFunctionGraph;
    function Nodes: TGraphNodes;               // every node once, inputs first
    function NodeCount: Integer;
    function ConsumerCount(const Node: TGraphNode): Integer;
    function OutputsOf(const Node: TGraphNode): TTextList;
    function ToText: String;

    function Optimise(Rules: TOptimiserRules; var Log: TTextList): TFunctionGraph;
    function Execute: TGraphRun;
    function ExecuteSeparately: TGraphRun;

    property Outputs: TGraphOutputs read FOutputs;
  end;

implementation

function VarText(const Value: Variant): String;
begin
  Result := Value;
end;

function JoinItems(const Items: TVarArray): String;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to High(Items) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + VarText(Items[i]);
  end;
  Result := Result + ']';
end;

{ TGraphNode }

constructor TGraphNode.CreateNode(Kind: TGraphKind; const Name: String;
  const Input: TGraphNode);
begin
  Inc(FNextId);
  FId := FNextId;
  FKind := Kind;
  FName := Name;
  FInput := Input;
end;

class procedure TGraphNode.ResetIds;
begin
  FNextId := 0;
end;

class function TGraphNode.Source(const Name: String; const Seq: TSequence): TGraphNode;
begin
  Result := TGraphNode.CreateNode(gkSource, Name, nil);
  Result.FSource := Seq;
end;

function TGraphNode.Derive(Kind: TGraphKind; const Name: String): TGraphNode;
begin
  if FKind = gkFold then
    raise EFunctional.Create('A Fold produces a single value - it can only be an output');
  Result := TGraphNode.CreateNode(Kind, Name, Self);
end;

function TGraphNode.Map(const Name: String; const Fn: TVarFunc): TGraphNode;
begin
  Result := Derive(gkMap, Name);
  Result.FMapFn := Fn;
end;

function TGraphNode.Identity: TGraphNode;
begin
  Result := Map('id', TVarFunction.Identity());
  Result.FIdentity := True;
end;

function TGraphNode.Filter(const Name: String; const Predicate: TVarPredicate): TGraphNode;
begin
  Result := Derive(gkFilter, Name);
  Result.FPredicate := Predicate;
end;

function TGraphNode.Take(Count: Integer): TGraphNode;
begin
  Result := Derive(gkTake, IntToStr(Count));
  Result.FLimit := Count;
end;

function TGraphNode.Drop(Count: Integer): TGraphNode;
begin
  Result := Derive(gkDrop, IntToStr(Count));
  Result.FLimit := Count;
end;

function TGraphNode.Scan(const Name: String; const Seed: Variant;
  const Fn: TVarFoldFunc): TGraphNode;
begin
  Result := Derive(gkScan, Name);
  Result.FSeed := Seed;
  Result.FFoldFn := Fn;
end;

function TGraphNode.Fold(const Name: String; const Seed: Variant;
  const Fn: TVarFoldFunc): TGraphNode;
begin
  Result := Derive(gkFold, Name);
  Result.FSeed := Seed;
  Result.FFoldFn := Fn;
end;

function TGraphNode.WithInput(const NewInput: TGraphNode): TGraphNode;
begin
  Result := TGraphNode.CreateNode(FKind, FName, NewInput);
  Result.FMapFn := FMapFn;
  Result.FPredicate := FPredicate;
  Result.FFoldFn := FFoldFn;
  Result.FSeed := FSeed;
  Result.FLimit := FLimit;
  Result.FSource := FSource;
  Result.FIdentity := FIdentity;
end;

function TGraphNode.Signature: String;
begin
  if FKind = gkSource then
    exit('source#' + IntToStr(FId));
  Result := KindText + '|' + FName + '|' + IntToStr(FLimit) + '|' + VarText(FSeed) +
    '|' + IntToStr(FInput.Id);
end;

function TGraphNode.KindText: String;
begin
  case FKind of
    gkSource: Result := 'Source';
    gkMap:    Result := 'Map';
    gkFilter: Result := 'Filter';
    gkTake:   Result := 'Take';
    gkDrop:   Result := 'Drop';
    gkScan:   Result := 'Scan';
    gkFold:   Result := 'Fold';
  end;
end;

function TGraphNode.Caption: String;
begin
  Result := KindText + ' ' + FName;
end;

function TGraphNode.Tag: String;
begin
  Result := 'n' + IntToStr(FId);
end;

{ TGraphRun }

function TGraphRun.Find(const OutputName: String): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(Names) do
    if Names[i] = OutputName then
      exit(i);
end;

function TGraphRun.AsText(Index: Integer): String;
begin
  if IsScalar[Index] then
    Result := VarText(Values[Index])
  else
    Result := JoinItems(Items[Index]);
end;

{ TFunctionGraph }

constructor TFunctionGraph.Create;
begin
end;

class function TFunctionGraph.AllRules: TOptimiserRules;
begin
  Result := [orMapFusion, orFilterFusion, orTakeDrop, orFoldFusion, orIdentity, orShareWork];
end;

class function TFunctionGraph.RuleTitle(Rule: TOptimiserRule): String;
begin
  case Rule of
    orMapFusion:    Result := 'Fuse Map . Map into one Map';
    orFilterFusion: Result := 'Fuse Filter . Filter into one Filter';
    orTakeDrop:     Result := 'Merge Take . Take and Drop . Drop';
    orFoldFusion:   Result := 'Move a Map into the Fold or Scan after it';
    orIdentity:     Result := 'Remove identity Maps';
    orShareWork:    Result := 'Share duplicate work between branches';
  end;
end;

function TFunctionGraph.Output(const Name: String; const Node: TGraphNode): TFunctionGraph;
var
  O: TGraphOutput;
  i: Integer;
begin
  Result := TFunctionGraph.Create;
  for i := 0 to High(FOutputs) do
    Result.FOutputs.Add(FOutputs[i]);
  O.Name := Name;
  O.Node := Node;
  Result.FOutputs.Add(O);
end;

function TFunctionGraph.IndexIn(const List: TGraphNodes; const Node: TGraphNode): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(List) do
    if List[i] = Node then
      exit(i);
end;

function TFunctionGraph.Nodes: TGraphNodes;
var
  Found: TGraphNodes;
  i: Integer;

  procedure Visit(const Node: TGraphNode);
  begin
    if (Node = nil) or (IndexIn(Found, Node) >= 0) then
      exit;
    Visit(Node.Input);       // inputs first
    Found.Add(Node);
  end;

begin
  for i := 0 to High(FOutputs) do
    Visit(FOutputs[i].Node);
  Result := Found;
end;

function TFunctionGraph.NodeCount: Integer;
begin
  Result := Length(Nodes);
end;

function TFunctionGraph.ConsumerCount(const Node: TGraphNode): Integer;
var
  All: TGraphNodes;
  i: Integer;
begin
  Result := 0;
  All := Nodes;
  for i := 0 to High(All) do
    if All[i].Input = Node then
      Inc(Result);
  for i := 0 to High(FOutputs) do
    if FOutputs[i].Node = Node then
      Inc(Result);
end;

function TFunctionGraph.OutputsOf(const Node: TGraphNode): TTextList;
var
  i: Integer;
begin
  for i := 0 to High(FOutputs) do
    if FOutputs[i].Node = Node then
      Result.Add(FOutputs[i].Name);
end;

function TFunctionGraph.ToText: String;
var
  All: TGraphNodes;
  Outs: TTextList;
  i, k: Integer;
  Line, Pad: String;
begin
  All := Nodes;
  Result := '';
  for i := 0 to High(All) do
  begin
    Line := All[i].Tag;
    while Length(Line) < 5 do
      Line := Line + ' ';
    Line := Line + '= ' + All[i].Caption;
    if All[i].Input <> nil then
    begin
      Pad := '';
      while Length(Line) + Length(Pad) < 40 do
        Pad := Pad + ' ';
      Line := Line + Pad + '<- ' + All[i].Input.Tag;
    end;
    Outs := OutputsOf(All[i]);
    for k := 0 to High(Outs) do
      Line := Line + '   => output "' + Outs[k] + '"';
    Result := Result + Line + #10;
  end;
end;

{ Optimiser }

function TFunctionGraph.RewritePass(Rules: TOptimiserRules; ShareOnly: Boolean;
  var Log: TTextList; var Changed: Boolean): TFunctionGraph;
var
  Old, NewOf, Canon: TGraphNodes;
  i, j: Integer;
  N, Inp, Rebuilt: TGraphNode;
  SingleUse: Boolean;
  Outer, Inner: TVarFunc;
  Step: TVarFoldFunc;
  P, Q: TVarPredicate;
  Sig, InTag: String;
  Made: TGraphNodes;
begin
  Old := Nodes;
  for i := 0 to High(Old) do
  begin
    N := Old[i];
    if N.Kind = gkSource then
    begin
      NewOf.Add(N);
      continue;
    end;

    Inp := NewOf[IndexIn(Old, N.Input)];
    SingleUse := ConsumerCount(N.Input) = 1;
    Rebuilt := nil;
    // Name the input as the reader can see it: a node made by a rule in
    // this pass is named in the log already; otherwise use the original
    if IndexIn(Made, Inp) >= 0 then
      InTag := Inp.Tag
    else
      InTag := N.Input.Tag;

    if not ShareOnly then
    begin
      // Identity removal
      if (orIdentity in Rules) and N.IsIdentity then
      begin
        Rebuilt := Inp;
        Log.Add('Removed identity ' + N.Tag + ' (Map id): it changes nothing');
      end

      // Map . Map
      else if (orMapFusion in Rules) and (N.Kind = gkMap) and (Inp.Kind = gkMap) and
        not Inp.IsIdentity then
      begin
        if SingleUse then
        begin
          Outer := N.MapFn;
          Inner := Inp.MapFn;
          Rebuilt := Inp.Input.Map(N.Name + ' . ' + Inp.Name,
            TVarFunction.Compose(Outer, Inner));
          Log.Add('Fused ' + InTag + ' Map ' + Inp.Name + ' and ' + N.Tag + ' Map ' + N.Name +
            ' into ' + Rebuilt.Tag + ' Map ' + Rebuilt.Name);
        end
        else
          Log.Add('Kept ' + N.Input.Tag + ' Map ' + Inp.Name + ' separate from ' + N.Tag +
            ': its result is also used elsewhere');
      end

      // Filter . Filter
      else if (orFilterFusion in Rules) and (N.Kind = gkFilter) and (Inp.Kind = gkFilter) then
      begin
        if SingleUse then
        begin
          P := Inp.Predicate;
          Q := N.Predicate;
          Rebuilt := Inp.Input.Filter(Inp.Name + ' and ' + N.Name, TVarFunction.Both(P, Q));
          Log.Add('Fused ' + InTag + ' Filter ' + Inp.Name + ' and ' + N.Tag + ' Filter ' +
            N.Name + ' into ' + Rebuilt.Tag + ' Filter ' + Rebuilt.Name);
        end
        else
          Log.Add('Kept ' + N.Input.Tag + ' Filter ' + Inp.Name + ' separate from ' + N.Tag +
            ': its result is also used elsewhere');
      end

      // Take . Take / Drop . Drop
      else if (orTakeDrop in Rules) and (N.Kind in [gkTake, gkDrop]) and
        (Inp.Kind = N.Kind) and SingleUse then
      begin
        if N.Kind = gkTake then
        begin
          if N.Limit < Inp.Limit then
            Rebuilt := Inp.Input.Take(N.Limit)
          else
            Rebuilt := Inp.Input.Take(Inp.Limit);
        end
        else
          Rebuilt := Inp.Input.Drop(Inp.Limit + N.Limit);
        Log.Add('Merged ' + InTag + ' ' + Inp.Caption + ' and ' + N.Tag + ' ' + N.Caption +
          ' into ' + Rebuilt.Tag + ' ' + Rebuilt.Caption);
      end

      // Map into a following Fold or Scan
      else if (orFoldFusion in Rules) and (N.Kind in [gkFold, gkScan]) and
        (Inp.Kind = gkMap) and SingleUse then
      begin
        Inner := Inp.MapFn;
        Step := N.FoldFn;
        if N.Kind = gkFold then
          Rebuilt := Inp.Input.Fold(N.Name + ' . ' + Inp.Name, N.Seed,
            function (Accumulator, Value: Variant): Variant
            begin
              Result := Step(Accumulator, Inner(Value));
            end)
        else
          Rebuilt := Inp.Input.Scan(N.Name + ' . ' + Inp.Name, N.Seed,
            function (Accumulator, Value: Variant): Variant
            begin
              Result := Step(Accumulator, Inner(Value));
            end);
        Log.Add('Moved ' + InTag + ' Map ' + Inp.Name + ' inside ' + N.Tag + ' ' + N.KindText +
          ' ' + N.Name + ', giving ' + Rebuilt.Tag + ' ' + Rebuilt.Caption);
      end;
    end;

    if Rebuilt = nil then
    begin
      if Inp = N.Input then
        Rebuilt := N
      else
        Rebuilt := N.WithInput(Inp);
    end
    else
    begin
      Changed := True;
      Made.Add(Rebuilt);
    end;

    // Share duplicate work: identical signature means identical computation
    if ShareOnly and (orShareWork in Rules) and (Rebuilt.Kind <> gkSource) then
    begin
      Sig := Rebuilt.Signature;
      for j := 0 to High(Canon) do
        if (Canon[j] <> Rebuilt) and (Canon[j].Signature = Sig) then
        begin
          Log.Add('Shared work: ' + Rebuilt.Tag + ' ' + Rebuilt.Caption +
            ' is the same as ' + Canon[j].Tag + ', so both branches now use ' + Canon[j].Tag);
          Rebuilt := Canon[j];
          Changed := True;
          break;
        end;
    end;
    if IndexIn(Canon, Rebuilt) < 0 then
      Canon.Add(Rebuilt);

    NewOf.Add(Rebuilt);
  end;

  Result := TFunctionGraph.Create;
  for i := 0 to High(FOutputs) do
    Result := Result.Output(FOutputs[i].Name, NewOf[IndexIn(Old, FOutputs[i].Node)]);
end;

function TFunctionGraph.Optimise(Rules: TOptimiserRules; var Log: TTextList): TFunctionGraph;
var
  Current: TFunctionGraph;
  Changed, Any: Boolean;
  Pass, Before: Integer;
begin
  Current := Self;
  Pass := 0;
  repeat
    Inc(Pass);
    Any := False;
    Before := Length(Log);

    Changed := False;
    Current := Current.RewritePass(Rules, True, Log, Changed);
    Any := Any or Changed;

    Changed := False;
    Current := Current.RewritePass(Rules, False, Log, Changed);
    Any := Any or Changed;

    // "Kept ... separate" notes repeat every pass; keep only the first set
    if (not Any) and (Pass > 1) then
      while Length(Log) > Before do
        Log.Delete(High(Log));
  until (not Any) or (Pass >= 10);

  if Length(Log) = 0 then
    Log.Add('Nothing to rewrite - the graph is already optimal for the selected rules');
  Result := Current;
end;

{ Execution }

procedure TFunctionGraph.CheckBounded;
var
  i: Integer;
  N: TGraphNode;
  Bounded: Boolean;
begin
  for i := 0 to High(FOutputs) do
  begin
    N := FOutputs[i].Node;
    Bounded := False;
    while N <> nil do
    begin
      if N.Kind = gkTake then
        Bounded := True;
      if (N.Kind = gkSource) and N.SourceSequence.IsBounded then
        Bounded := True;
      N := N.Input;
    end;
    if not Bounded then
      raise EFunctional.Create('Output "' + FOutputs[i].Name +
        '" would never finish: its source is infinite and there is no Take before it');
  end;
end;

type
  TIntLists = array of TIntArray;
  TFlags = array of Boolean;
  TDeliver = function (Index: Integer; Value: Variant): Boolean;

function TFunctionGraph.Execute: TGraphRun;
var
  Run: TGraphRun;
  All: TGraphNodes;
  Children, OutIndex: TIntLists;
  Counters: TIntArray;
  Accs: TVarArray;
  Active: TFlags;
  Deliver: TDeliver;
  i, k, s, Parent: Integer;
  Empty: TVarArray;
  Wanted: Boolean;
  SourceIndex: Integer;
  NoInts: TIntArray;
begin
  Run := TGraphRun.Create;
  Result := Run;
  try
    CheckBounded;
  except
    on E: Exception do
    begin
      Run.Error := E.Message;
      exit;
    end;
  end;

  All := Nodes;
  for i := 0 to High(All) do
  begin
    NoInts := [];
    Children.Add(NoInts);
    NoInts := [];
    OutIndex.Add(NoInts);
    Counters.Add(0);
    Accs.Add(All[i].Seed);
    Active.Add(True);
  end;
  for i := 0 to High(All) do
    if All[i].Input <> nil then
    begin
      Parent := IndexIn(All, All[i].Input);
      Children[Parent].Add(i);
    end;
  for k := 0 to High(FOutputs) do
  begin
    Run.Names.Add(FOutputs[k].Name);
    Run.IsScalar.Add(FOutputs[k].Node.Kind = gkFold);
    Run.Values.Add(FOutputs[k].Node.Seed);
    Empty := [];
    Run.Items.Add(Empty);
    OutIndex[IndexIn(All, FOutputs[k].Node)].Add(k);
  end;

  // Push one value into node Index; returns False once that branch is finished
  Deliver := function (Index: Integer; Value: Variant): Boolean
    var
      N: TGraphNode;
      V: Variant;
      Last, Wants: Boolean;
      c, o: Integer;
    begin
      if not Active[Index] then
        exit(False);
      N := All[Index];
      V := Value;
      Last := False;

      case N.Kind of
        gkMap:
          begin
            Inc(Run.Calls);
            V := N.MapFn(V);
          end;
        gkFilter:
          begin
            Inc(Run.Calls);
            if not N.Predicate(V) then
              exit(True);
          end;
        gkDrop:
          if Counters[Index] < N.Limit then
          begin
            Counters[Index] := Counters[Index] + 1;
            exit(True);
          end;
        gkTake:
          begin
            if Counters[Index] >= N.Limit then
            begin
              Active[Index] := False;
              exit(False);
            end;
            Counters[Index] := Counters[Index] + 1;
            if Counters[Index] >= N.Limit then
              Last := True;
          end;
        gkScan:
          begin
            Inc(Run.Calls);
            Accs[Index] := N.FoldFn(Accs[Index], V);
            V := Accs[Index];
          end;
        gkFold:
          begin
            Inc(Run.Calls);
            Accs[Index] := N.FoldFn(Accs[Index], V);
            for o := 0 to High(OutIndex[Index]) do
              Run.Values[OutIndex[Index][o]] := Accs[Index];
            exit(True);
          end;
      end;

      // Collect for list outputs attached here
      Wants := Length(OutIndex[Index]) > 0;
      for o := 0 to High(OutIndex[Index]) do
        Run.Items[OutIndex[Index][o]].Add(V);

      // Fan out to every consumer that still wants values
      for c := 0 to High(Children[Index]) do
        if Active[Children[Index][c]] then
        begin
          if Deliver(Children[Index][c], V) then
            Wants := True
          else
            Active[Children[Index][c]] := False;
        end;

      if Last then
      begin
        Active[Index] := False;
        Wants := False;
      end;
      Result := Wants;
    end;

  // Drive each source once. TakeWhile(Wanted) lets the graph stop the source.
  for s := 0 to High(All) do
    if All[s].Kind = gkSource then
    begin
      Wanted := True;
      SourceIndex := s;
      All[s].SourceSequence
        .TakeWhile(function (Value: Variant): Boolean
          begin
            Result := Wanted;
          end)
        .Fold(0, function (Accumulator, Value: Variant): Variant
          begin
            Inc(Run.SourcePulls);
            Wanted := Deliver(SourceIndex, Value);
            Result := Accumulator;
          end);
    end;
end;

function TFunctionGraph.ExecuteSeparately: TGraphRun;
var
  Run: TGraphRun;
  k, i: Integer;
  Path: TGraphNodes;
  N: TGraphNode;
  Seq: TSequence;
  F: TVarFunc;
  P: TVarPredicate;
  G: TVarFoldFunc;
  Empty: TVarArray;

  function CountedMap(const Fn: TVarFunc): TVarFunc;
  var
    Inner: TVarFunc;
  begin
    Inner := Fn;
    Result := function (Value: Variant): Variant
      begin
        Inc(Run.Calls);
        Result := Inner(Value);
      end;
  end;

  function CountedPredicate(const Fn: TVarPredicate): TVarPredicate;
  var
    Inner: TVarPredicate;
  begin
    Inner := Fn;
    Result := function (Value: Variant): Boolean
      begin
        Inc(Run.Calls);
        Result := Inner(Value);
      end;
  end;

  function CountedFold(const Fn: TVarFoldFunc): TVarFoldFunc;
  var
    Inner: TVarFoldFunc;
  begin
    Inner := Fn;
    Result := function (Accumulator, Value: Variant): Variant
      begin
        Inc(Run.Calls);
        Result := Inner(Accumulator, Value);
      end;
  end;

begin
  Run := TGraphRun.Create;
  Result := Run;
  try
    CheckBounded;
  except
    on E: Exception do
    begin
      Run.Error := E.Message;
      exit;
    end;
  end;

  for k := 0 to High(FOutputs) do
  begin
    // Walk back from the output to its source, then rebuild as one TSequence
    Path := [];
    N := FOutputs[k].Node;
    while N <> nil do
    begin
      Path.Insert(0, N);
      N := N.Input;
    end;

    Seq := Path[0].SourceSequence.Map(function (Value: Variant): Variant
      begin
        Inc(Run.SourcePulls);
        Result := Value;
      end);

    Run.Names.Add(FOutputs[k].Name);
    Run.IsScalar.Add(FOutputs[k].Node.Kind = gkFold);
    Run.Values.Add(FOutputs[k].Node.Seed);
    Empty := [];
    Run.Items.Add(Empty);

    for i := 1 to High(Path) do
    begin
      N := Path[i];
      case N.Kind of
        gkMap:    Seq := Seq.Map(CountedMap(N.MapFn));
        gkFilter: Seq := Seq.Filter(CountedPredicate(N.Predicate));
        gkTake:   Seq := Seq.Take(N.Limit);
        gkDrop:   Seq := Seq.Drop(N.Limit);
        gkScan:   Seq := Seq.Scan(N.Seed, CountedFold(N.FoldFn));
        gkFold:   Run.Values[k] := Seq.Fold(N.Seed, CountedFold(N.FoldFn));
      end;
    end;
    if FOutputs[k].Node.Kind <> gkFold then
      Run.Items[k] := Seq.ToArray;
  end;
end;

end.
