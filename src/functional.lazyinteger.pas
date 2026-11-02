unit functional.lazyinteger;

// ---------------------------------------------------------------------------
//  qtxFunctional - TLazyInteger
//
//  A lazy, immutable stream of integers.
//
//  * Lazy       : Map / Filter / Take only record a pipeline stage. No source
//                 element is produced until a terminal operation (Fold,
//                 ToArray, Count, AsString) runs. Infinite sources are fine
//                 as long as a Take bounds them.
//  * Immutable  : every operation returns a NEW TLazyInteger; the receiver is
//                 never modified, so pipelines can be branched and reused.
//  * Fusion     : the whole pipeline runs as ONE pass with no intermediate
//                 arrays, and adjacent stages are merged when built:
//                   Map(f).Map(g)       -> Map(g . f)
//                   Filter(p).Filter(q) -> Filter(p and q)
//                   Take(n).Take(m)     -> Take(min(n, m))
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.stats;

type
  TLazyStageKind = (skMap, skFilter, skTake);

  TLazyStage = record
    Kind:     TLazyStageKind;
    MapFn:    TIntFunc;
    FilterFn: TIntPredicate;
    Limit:    Integer;
  end;

  TLazyStages = array of TLazyStage;

  TLazyInteger = class
  private
    FSource:      TIntGenerator;   // Index -> element
    FSourceCount: Integer;         // -1 = infinite
    FStages:      TLazyStages;
    function  CloneStages: TLazyStages;
    function  IsBounded: Boolean;
    function  Derive(const Stages: TLazyStages): TLazyInteger;
    procedure Run(const Sink: TIntSink);
  public
    constructor Create(const Source: TIntGenerator; SourceCount: Integer;
      const Stages: TLazyStages);

    // Sources
    class function Range(First, Last: Integer): TLazyInteger;    // finite, inclusive
    class function From(Start: Integer): TLazyInteger;           // infinite: Start, Start+1, ...
    class function Generate(const Fn: TIntGenerator): TLazyInteger; // infinite: Fn(0), Fn(1), ...
    class function FromArray(const Values: TIntArray): TLazyInteger;

    // Lazy transformations (return new instances)
    function Map(const Fn: TIntFunc): TLazyInteger;
    function Filter(const Predicate: TIntPredicate): TLazyInteger;
    function Take(Count: Integer): TLazyInteger;

    // Terminal operations (force evaluation)
    function Fold(Seed: Integer; const Fn: TIntFoldFunc): Integer;
    function ToArray: TIntArray;
    function Count: Integer;
    function AsString: String;

    // Number of stages after fusion - useful for inspecting the pipeline
    function StageCount: Integer;
  end;

implementation

{ TLazyInteger }

constructor TLazyInteger.Create(const Source: TIntGenerator;
  SourceCount: Integer; const Stages: TLazyStages);
begin
  FSource := Source;
  FSourceCount := SourceCount;
  FStages := Stages;
  Inc(TFunctionalStats.PipelineObjects);
end;

function TLazyInteger.CloneStages: TLazyStages;
var
  i: Integer;
begin
  for i := 0 to High(FStages) do
    Result.Add(FStages[i]);
end;

function TLazyInteger.IsBounded: Boolean;
var
  i: Integer;
begin
  Result := FSourceCount >= 0;
  if not Result then
    for i := 0 to High(FStages) do
      if FStages[i].Kind = skTake then
        exit(True);
end;

function TLazyInteger.Derive(const Stages: TLazyStages): TLazyInteger;
begin
  Result := TLazyInteger.Create(FSource, FSourceCount, Stages);
end;

function TLazyInteger.StageCount: Integer;
begin
  Result := Length(FStages);
end;

{ Sources }

class function TLazyInteger.Range(First, Last: Integer): TLazyInteger;
var
  Start, Total: Integer;
  NoStages: TLazyStages;
begin
  Start := First;
  Total := Last - First + 1;
  if Total < 0 then
    Total := 0;
  Result := TLazyInteger.Create(
    function (Index: Integer): Integer
    begin
      Result := Start + Index;
    end,
    Total, NoStages);
end;

class function TLazyInteger.From(Start: Integer): TLazyInteger;
var
  Origin: Integer;
  NoStages: TLazyStages;
begin
  Origin := Start;
  Result := TLazyInteger.Create(
    function (Index: Integer): Integer
    begin
      Result := Origin + Index;
    end,
    -1, NoStages);
end;

class function TLazyInteger.Generate(const Fn: TIntGenerator): TLazyInteger;
var
  NoStages: TLazyStages;
begin
  Result := TLazyInteger.Create(Fn, -1, NoStages);
end;

class function TLazyInteger.FromArray(const Values: TIntArray): TLazyInteger;
var
  Data: TIntArray;
  NoStages: TLazyStages;
  i: Integer;
begin
  // Defensive copy - later changes to the caller's array cannot leak in
  for i := 0 to High(Values) do
    Data.Add(Values[i]);
  Result := TLazyInteger.Create(
    function (Index: Integer): Integer
    begin
      Result := Data[Index];
    end,
    Length(Data), NoStages);
end;

{ Lazy transformations }

function TLazyInteger.Map(const Fn: TIntFunc): TLazyInteger;
var
  Stages: TLazyStages;
  Stage: TLazyStage;
  Last: Integer;
begin
  Stages := CloneStages;
  Last := High(Stages);
  if (Last >= 0) and (Stages[Last].Kind = skMap) then
  begin
    // Map fusion: Map(f).Map(g) = Map(g . f)
    Stage := Stages[Last];
    Stage.MapFn := TFunction.AndThen(Stage.MapFn, Fn);
    Stages[Last] := Stage;
  end
  else
  begin
    Stage.Kind := skMap;
    Stage.MapFn := Fn;
    Stages.Add(Stage);
  end;
  Result := Derive(Stages);
end;

function TLazyInteger.Filter(const Predicate: TIntPredicate): TLazyInteger;
var
  Stages: TLazyStages;
  Stage: TLazyStage;
  Last: Integer;
begin
  Stages := CloneStages;
  Last := High(Stages);
  if (Last >= 0) and (Stages[Last].Kind = skFilter) then
  begin
    // Filter fusion: Filter(p).Filter(q) = Filter(p and q)
    Stage := Stages[Last];
    Stage.FilterFn := TFunction.Both(Stage.FilterFn, Predicate);
    Stages[Last] := Stage;
  end
  else
  begin
    Stage.Kind := skFilter;
    Stage.FilterFn := Predicate;
    Stages.Add(Stage);
  end;
  Result := Derive(Stages);
end;

function TLazyInteger.Take(Count: Integer): TLazyInteger;
var
  Stages: TLazyStages;
  Stage: TLazyStage;
  Last: Integer;
begin
  if Count < 0 then
    Count := 0;
  Stages := CloneStages;
  Last := High(Stages);
  if (Last >= 0) and (Stages[Last].Kind = skTake) then
  begin
    // Take fusion: Take(n).Take(m) = Take(min(n, m))
    Stage := Stages[Last];
    if Count < Stage.Limit then
      Stage.Limit := Count;
    Stages[Last] := Stage;
  end
  else
  begin
    Stage.Kind := skTake;
    Stage.Limit := Count;
    Stages.Add(Stage);
  end;
  Result := Derive(Stages);
end;

{ Evaluation - a single fused pass over the source }

procedure TLazyInteger.Run(const Sink: TIntSink);
var
  Index, Value, s: Integer;
  Taken: TIntArray;
  Pass, Stop: Boolean;
begin
  if not IsBounded then
    raise EFunctional.Create(
      'TLazyInteger: infinite stream must be bounded with Take before evaluation');

  // Per-run counters keep the pipeline itself immutable and re-runnable
  for s := 0 to High(FStages) do
    Taken.Add(0);

  Index := 0;
  Stop := False;
  while not Stop do
  begin
    if (FSourceCount >= 0) and (Index >= FSourceCount) then
      break;

    Value := FSource(Index);
    Inc(TFunctionalStats.SourceElements);
    Inc(Index);
    Pass := True;

    for s := 0 to High(FStages) do
    begin
      case FStages[s].Kind of
        skMap:
          Value := FStages[s].MapFn(Value);

        skFilter:
          if not FStages[s].FilterFn(Value) then
          begin
            Pass := False;
            break;
          end;

        skTake:
          begin
            if Taken[s] >= FStages[s].Limit then
            begin
              Pass := False;
              Stop := True;
              break;
            end;
            Taken[s] := Taken[s] + 1;
            // Once any Take is full nothing more can ever reach the sink,
            // so finish after delivering this element.
            if Taken[s] >= FStages[s].Limit then
              Stop := True;
          end;
      end;
    end;

    if Pass then
      if not Sink(Value) then
        Stop := True;
  end;
end;

{ Terminal operations }

function TLazyInteger.Fold(Seed: Integer; const Fn: TIntFoldFunc): Integer;
var
  Acc: Integer;
  Reducer: TIntFoldFunc;
begin
  Acc := Seed;
  Reducer := Fn;
  Run(function (Value: Integer): Boolean
    begin
      Acc := Reducer(Acc, Value);
      Result := True;
    end);
  Result := Acc;
end;

function TLazyInteger.ToArray: TIntArray;
var
  Items: TIntArray;
begin
  Run(function (Value: Integer): Boolean
    begin
      Items.Add(Value);
      Result := True;
    end);
  Result := Items;
end;

function TLazyInteger.Count: Integer;
begin
  Result := Fold(0,
    function (Accumulator, Value: Integer): Integer
    begin
      Result := Accumulator + 1;
    end);
end;

function TLazyInteger.AsString: String;
var
  Items: TIntArray;
  i: Integer;
begin
  Items := ToArray;
  Result := '[';
  for i := 0 to High(Items) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + IntToStr(Items[i]);
  end;
  Result := Result + ']';
end;

end.
