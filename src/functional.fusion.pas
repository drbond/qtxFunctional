unit functional.fusion;

// ---------------------------------------------------------------------------
//  qtxFunctional - TFusion
//
//  The pipeline engine behind TSequence. A pipeline is an immutable list of
//  stages. TFusion does two jobs:
//
//  1. Build-time fusion - when a stage is appended, adjacent compatible
//     stages are rewritten into one (the classic "rewrite rules"):
//
//        Map f  . Map g           ->  Map (g . f)
//        Filter p . Filter q      ->  Filter (p and q)
//        Take n . Take m          ->  Take (min n m)
//        Drop n . Drop m          ->  Drop (n + m)
//        Map f  . Scan s g        ->  Scan s (\acc x -> g acc (f x))
//
//  2. Run-time fusion - Execute composes ALL stages into a single push
//     function that the source feeds. One pass, no intermediate
//     collections, and early termination flows back to the source as soon
//     as a Take / TakeWhile is satisfied (like foldr/build fusion in GHC).
//
//  Stage kinds:
//     Map, Filter, Take, Drop, TakeWhile
//     Scan     running accumulation; emits each new accumulator
//     FlatMap  each value expands into a sub-source whose elements flow
//              through the REMAINING stages; a later Take stops the
//              sub-source and the outer source alike
//
//  Stateful stages (Take, Drop, Scan) keep their state per execution, so a
//  pipeline can be run any number of times with identical results.
//
//  Every Append* call returns a NEW stage list; inputs are never modified.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions;

type
  TFusionKind = (fkMap, fkFilter, fkTake, fkDrop, fkTakeWhile, fkScan, fkFlatMap);

  TVarExpand = function (Value: Variant): TVarSource;

  TFusionStage = record
    Kind:      TFusionKind;
    MapFn:     TVarFunc;
    Predicate: TVarPredicate;
    FoldFn:    TVarFoldFunc;
    ExpandFn:  TVarExpand;
    Seed:      Variant;
    Limit:     Integer;
    Fused:     Integer;   // how many source-level stages this one stands for
  end;

  TFusionStages = array of TFusionStage;

  TStageProcessor = function (Item: Variant; Start: Integer): Boolean;

  TFusion = class
  private
    class function Clone(const Stages: TFusionStages): TFusionStages;
    class function Push(const Stages: TFusionStages;
      const Stage: TFusionStage): TFusionStages;
  public
    class function AppendMap(const Stages: TFusionStages;
      const Fn: TVarFunc): TFusionStages;
    class function AppendFilter(const Stages: TFusionStages;
      const Predicate: TVarPredicate): TFusionStages;
    class function AppendTake(const Stages: TFusionStages;
      Count: Integer): TFusionStages;
    class function AppendDrop(const Stages: TFusionStages;
      Count: Integer): TFusionStages;
    class function AppendTakeWhile(const Stages: TFusionStages;
      const Predicate: TVarPredicate): TFusionStages;
    class function AppendScan(const Stages: TFusionStages;
      const Seed: Variant; const Fn: TVarFoldFunc): TFusionStages;
    class function AppendFlatMap(const Stages: TFusionStages;
      const Fn: TVarExpand): TFusionStages;

    // True if some stage guarantees the stream ends (Take / TakeWhile)
    class function IsBounded(const Stages: TFusionStages): Boolean;

    // Human-readable plan, e.g. "Map{x3} -> Filter -> Take(5)"
    class function Describe(const Stages: TFusionStages): String;

    // Run Source through all stages into Sink, as one fused pass
    class procedure Execute(const Source: TVarSource;
      const Stages: TFusionStages; const Sink: TVarSink);
  end;

implementation

class function TFusion.Clone(const Stages: TFusionStages): TFusionStages;
var
  i: Integer;
begin
  for i := 0 to High(Stages) do
    Result.Add(Stages[i]);
end;

class function TFusion.Push(const Stages: TFusionStages;
  const Stage: TFusionStage): TFusionStages;
begin
  Result := Clone(Stages);
  Result.Add(Stage);
end;

class function TFusion.AppendMap(const Stages: TFusionStages;
  const Fn: TVarFunc): TFusionStages;
var
  Stage: TFusionStage;
  Last: Integer;
begin
  Last := High(Stages);
  if (Last >= 0) and (Stages[Last].Kind = fkMap) then
  begin
    Result := Clone(Stages);
    Stage := Result[Last];
    Stage.MapFn := TVarFunction.AndThen(Stage.MapFn, Fn);
    Stage.Fused := Stage.Fused + 1;
    Result[Last] := Stage;
  end
  else
  begin
    Stage.Kind := fkMap;
    Stage.MapFn := Fn;
    Stage.Fused := 1;
    Result := Push(Stages, Stage);
  end;
end;

class function TFusion.AppendFilter(const Stages: TFusionStages;
  const Predicate: TVarPredicate): TFusionStages;
var
  Stage: TFusionStage;
  Last: Integer;
begin
  Last := High(Stages);
  if (Last >= 0) and (Stages[Last].Kind = fkFilter) then
  begin
    Result := Clone(Stages);
    Stage := Result[Last];
    Stage.Predicate := TVarFunction.Both(Stage.Predicate, Predicate);
    Stage.Fused := Stage.Fused + 1;
    Result[Last] := Stage;
  end
  else
  begin
    Stage.Kind := fkFilter;
    Stage.Predicate := Predicate;
    Stage.Fused := 1;
    Result := Push(Stages, Stage);
  end;
end;

class function TFusion.AppendTake(const Stages: TFusionStages;
  Count: Integer): TFusionStages;
var
  Stage: TFusionStage;
  Last: Integer;
begin
  if Count < 0 then
    Count := 0;
  Last := High(Stages);
  if (Last >= 0) and (Stages[Last].Kind = fkTake) then
  begin
    Result := Clone(Stages);
    Stage := Result[Last];
    if Count < Stage.Limit then
      Stage.Limit := Count;
    Stage.Fused := Stage.Fused + 1;
    Result[Last] := Stage;
  end
  else
  begin
    Stage.Kind := fkTake;
    Stage.Limit := Count;
    Stage.Fused := 1;
    Result := Push(Stages, Stage);
  end;
end;

class function TFusion.AppendDrop(const Stages: TFusionStages;
  Count: Integer): TFusionStages;
var
  Stage: TFusionStage;
  Last: Integer;
begin
  if Count <= 0 then
    exit(Clone(Stages));   // Drop(0) is the identity - no stage at all
  Last := High(Stages);
  if (Last >= 0) and (Stages[Last].Kind = fkDrop) then
  begin
    Result := Clone(Stages);
    Stage := Result[Last];
    Stage.Limit := Stage.Limit + Count;
    Stage.Fused := Stage.Fused + 1;
    Result[Last] := Stage;
  end
  else
  begin
    Stage.Kind := fkDrop;
    Stage.Limit := Count;
    Stage.Fused := 1;
    Result := Push(Stages, Stage);
  end;
end;

class function TFusion.AppendTakeWhile(const Stages: TFusionStages;
  const Predicate: TVarPredicate): TFusionStages;
var
  Stage: TFusionStage;
begin
  Stage.Kind := fkTakeWhile;
  Stage.Predicate := Predicate;
  Stage.Fused := 1;
  Result := Push(Stages, Stage);
end;

class function TFusion.AppendScan(const Stages: TFusionStages;
  const Seed: Variant; const Fn: TVarFoldFunc): TFusionStages;
var
  Stage: TFusionStage;
  Last: Integer;
  Pre: TVarFunc;
  Step: TVarFoldFunc;
begin
  Last := High(Stages);
  Step := Fn;
  Stage.Kind := fkScan;
  Stage.Seed := Seed;

  if (Last >= 0) and (Stages[Last].Kind = fkMap) then
  begin
    // Map/scan fusion: the mapping moves inside the accumulator step
    Pre := Stages[Last].MapFn;
    Stage.FoldFn := function (Accumulator, Value: Variant): Variant
      begin
        Result := Step(Accumulator, Pre(Value));
      end;
    Stage.Fused := Stages[Last].Fused + 1;
    Result := Clone(Stages);
    Result[Last] := Stage;
  end
  else
  begin
    Stage.FoldFn := Step;
    Stage.Fused := 1;
    Result := Push(Stages, Stage);
  end;
end;

class function TFusion.AppendFlatMap(const Stages: TFusionStages;
  const Fn: TVarExpand): TFusionStages;
var
  Stage: TFusionStage;
begin
  Stage.Kind := fkFlatMap;
  Stage.ExpandFn := Fn;
  Stage.Fused := 1;
  Result := Push(Stages, Stage);
end;

class function TFusion.IsBounded(const Stages: TFusionStages): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(Stages) do
    if Stages[i].Kind in [fkTake, fkTakeWhile] then
      exit(True);
end;

class function TFusion.Describe(const Stages: TFusionStages): String;
var
  i: Integer;
  Part: String;
begin
  Result := '';
  for i := 0 to High(Stages) do
  begin
    case Stages[i].Kind of
      fkMap:       Part := 'Map';
      fkFilter:    Part := 'Filter';
      fkTake:      Part := 'Take(' + IntToStr(Stages[i].Limit) + ')';
      fkDrop:      Part := 'Drop(' + IntToStr(Stages[i].Limit) + ')';
      fkTakeWhile: Part := 'TakeWhile';
      fkScan:      Part := 'Scan';
      fkFlatMap:   Part := 'FlatMap';
    end;
    if Stages[i].Fused > 1 then
      Part := Part + '{x' + IntToStr(Stages[i].Fused) + '}';
    if Result <> '' then
      Result := Result + ' -> ';
    Result := Result + Part;
  end;
end;

class procedure TFusion.Execute(const Source: TVarSource;
  const Stages: TFusionStages; const Sink: TVarSink);
var
  Plan: TFusionStages;
  Counters: TIntArray;
  Accumulators: TVarArray;
  Target: TVarSink;
  Process: TStageProcessor;
  s: Integer;
begin
  Plan := Stages;
  Target := Sink;

  // Per-execution state: pipelines stay immutable and re-runnable
  for s := 0 to High(Plan) do
  begin
    Counters.Add(0);
    Accumulators.Add(Plan[s].Seed);
  end;

  // Push one item through the stages from Start onwards.
  // Returns False when the whole pipeline should stop.
  Process := function (Item: Variant; Start: Integer): Boolean
    var
      Value: Variant;
      i, Next: Integer;
      Finished, Halted: Boolean;
      Inner: TVarSource;
    begin
      Value := Item;
      Finished := False;

      for i := Start to High(Plan) do
      begin
        case Plan[i].Kind of
          fkMap:
            Value := Plan[i].MapFn(Value);

          fkFilter:
            if not Plan[i].Predicate(Value) then
              exit(True);

          fkDrop:
            if Counters[i] < Plan[i].Limit then
            begin
              Counters[i] := Counters[i] + 1;
              exit(True);
            end;

          fkTake:
            begin
              if Counters[i] >= Plan[i].Limit then
                exit(False);
              Counters[i] := Counters[i] + 1;
              // Full now: deliver this element, then stop
              if Counters[i] >= Plan[i].Limit then
                Finished := True;
            end;

          fkTakeWhile:
            if not Plan[i].Predicate(Value) then
              exit(False);

          fkScan:
            begin
              Accumulators[i] := Plan[i].FoldFn(Accumulators[i], Value);
              Value := Accumulators[i];
            end;

          fkFlatMap:
            begin
              Next := i + 1;
              Halted := False;
              Inner := Plan[i].ExpandFn(Value);
              Inner(function (Sub: Variant): Boolean
                begin
                  Result := Process(Sub, Next);
                  if not Result then
                    Halted := True;
                end);
              exit((not Halted) and (not Finished));
            end;
        end;
      end;

      if not Target(Value) then
        exit(False);
      Result := not Finished;
    end;

  Source(function (Item: Variant): Boolean
    begin
      Result := Process(Item, 0);
    end);
end;

end.
