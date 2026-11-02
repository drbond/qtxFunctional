unit functional.sequence;

// ---------------------------------------------------------------------------
//  qtxFunctional - TSequence
//
//  A lazy, immutable, general-purpose stream of Variant values (Quartex has
//  no generics; Variant fills that role).
//
//    * Lazy       - stages are only recorded; terminal operations (Fold,
//                   ToArray, Count, AsString) do the work. FoldLazy and
//                   Head defer even that.
//    * Immutable  - every operation returns a new TSequence.
//    * Fused      - stages are merged by TFusion and run in a single pass.
//
//  Sources are *push* procedures: each run calls the source afresh, so
//  stateful generators such as Iterate restart cleanly every time.
//
//  Zipping and push sources: a push source cannot be paused, so two push
//  sequences cannot be walked in lock-step. ZipWith therefore materialises
//  the (bounded) partner once per run; ZipWithList walks a pull-based
//  TLazyList partner instead, which may be infinite.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.lazy,
  functional.lazylist,
  functional.fusion;

type
  TSequence = class;

  TSequenceBinder = function (Value: Variant): TSequence;

  TSequence = class
  private
    FSource:     TVarSource;
    FSourceName: String;
    FInfinite:   Boolean;
    FStages:     TFusionStages;
    function  Derive(const Stages: TFusionStages): TSequence;
    procedure Run(const Sink: TVarSink);
    procedure RunUnchecked(const Sink: TVarSink);
  public
    constructor Create(const Source: TVarSource; const SourceName: String;
      Infinite: Boolean; const Stages: TFusionStages);

    // Sources
    class function Range(First, Last: Integer): TSequence;              // finite
    class function From(Start: Integer): TSequence;                     // infinite
    class function Iterate(const Seed: Variant; const Next: TVarFunc): TSequence; // infinite
    class function Replicate(const Value: Variant; Count: Integer): TSequence;
    class function FromArray(const Values: TVarArray): TSequence;

    // Lazy transformations
    function Map(const Fn: TVarFunc): TSequence;
    function Filter(const Predicate: TVarPredicate): TSequence;
    function Take(Count: Integer): TSequence;
    function Drop(Count: Integer): TSequence;
    function TakeWhile(const Predicate: TVarPredicate): TSequence;
    function Scan(const Seed: Variant; const Fn: TVarFoldFunc): TSequence;
    function FlatMap(const Fn: TSequenceBinder): TSequence;

    // Combining sequences
    function ZipWith(const Other: TSequence; const Fn: TVarFoldFunc): TSequence;
    function ZipWithList(const List: TLazyList; const Fn: TVarFoldFunc): TSequence;

    // Terminal operations
    function Fold(const Seed: Variant; const Fn: TVarFoldFunc): Variant;
    function ToArray: TVarArray;
    function Count: Integer;
    function AsString: String;

    // Deferred terminal operations - nothing runs until .Value is read
    function FoldLazy(const Seed: Variant; const Fn: TVarFoldFunc): TLazy;
    function Head: TLazy;

    // Introspection
    function IsBounded: Boolean;
    function Describe: String;
    function StageCount: Integer;
  end;

implementation

{ TSequence }

constructor TSequence.Create(const Source: TVarSource; const SourceName: String;
  Infinite: Boolean; const Stages: TFusionStages);
begin
  FSource := Source;
  FSourceName := SourceName;
  FInfinite := Infinite;
  FStages := Stages;
end;

function TSequence.Derive(const Stages: TFusionStages): TSequence;
begin
  Result := TSequence.Create(FSource, FSourceName, FInfinite, Stages);
end;

function TSequence.IsBounded: Boolean;
begin
  Result := (not FInfinite) or TFusion.IsBounded(FStages);
end;

procedure TSequence.Run(const Sink: TVarSink);
begin
  if not IsBounded then
    raise EFunctional.Create(
      'TSequence: infinite sequence must be bounded with Take or TakeWhile before evaluation');
  RunUnchecked(Sink);
end;

procedure TSequence.RunUnchecked(const Sink: TVarSink);
begin
  TFusion.Execute(FSource, FStages, Sink);
end;

{ Sources }

class function TSequence.Range(First, Last: Integer): TSequence;
var
  Lo, Hi: Integer;
  NoStages: TFusionStages;
begin
  Lo := First;
  Hi := Last;
  Result := TSequence.Create(
    procedure (const Sink: TVarSink)
    var
      i: Integer;
    begin
      for i := Lo to Hi do
        if not Sink(i) then
          exit;
    end,
    'Range(' + IntToStr(First) + '..' + IntToStr(Last) + ')', False, NoStages);
end;

class function TSequence.From(Start: Integer): TSequence;
var
  Origin: Integer;
  NoStages: TFusionStages;
begin
  Origin := Start;
  Result := TSequence.Create(
    procedure (const Sink: TVarSink)
    var
      n: Integer;
    begin
      n := Origin;
      while Sink(n) do
        Inc(n);
    end,
    'From(' + IntToStr(Start) + ')', True, NoStages);
end;

class function TSequence.Iterate(const Seed: Variant; const Next: TVarFunc): TSequence;
var
  First: Variant;
  Step: TVarFunc;
  NoStages: TFusionStages;
begin
  First := Seed;
  Step := Next;
  Result := TSequence.Create(
    procedure (const Sink: TVarSink)
    var
      Current: Variant;
    begin
      Current := First;
      // Next is only applied once the consumer has asked for more
      while Sink(Current) do
        Current := Step(Current);
    end,
    'Iterate', True, NoStages);
end;

class function TSequence.Replicate(const Value: Variant; Count: Integer): TSequence;
var
  Item: Variant;
  Total: Integer;
  NoStages: TFusionStages;
begin
  Item := Value;
  Total := Count;
  Result := TSequence.Create(
    procedure (const Sink: TVarSink)
    var
      i: Integer;
    begin
      for i := 1 to Total do
        if not Sink(Item) then
          exit;
    end,
    'Replicate(' + IntToStr(Count) + ')', False, NoStages);
end;

class function TSequence.FromArray(const Values: TVarArray): TSequence;
var
  Data: TVarArray;
  NoStages: TFusionStages;
  i: Integer;
begin
  // Defensive copy: later changes to the caller's array cannot leak in
  for i := 0 to High(Values) do
    Data.Add(Values[i]);
  Result := TSequence.Create(
    procedure (const Sink: TVarSink)
    var
      k: Integer;
    begin
      for k := 0 to High(Data) do
        if not Sink(Data[k]) then
          exit;
    end,
    'Array[' + IntToStr(Length(Data)) + ']', False, NoStages);
end;

{ Lazy transformations }

function TSequence.Map(const Fn: TVarFunc): TSequence;
begin
  Result := Derive(TFusion.AppendMap(FStages, Fn));
end;

function TSequence.Filter(const Predicate: TVarPredicate): TSequence;
begin
  Result := Derive(TFusion.AppendFilter(FStages, Predicate));
end;

function TSequence.Take(Count: Integer): TSequence;
begin
  Result := Derive(TFusion.AppendTake(FStages, Count));
end;

function TSequence.Drop(Count: Integer): TSequence;
begin
  Result := Derive(TFusion.AppendDrop(FStages, Count));
end;

function TSequence.TakeWhile(const Predicate: TVarPredicate): TSequence;
begin
  Result := Derive(TFusion.AppendTakeWhile(FStages, Predicate));
end;

function TSequence.Scan(const Seed: Variant; const Fn: TVarFoldFunc): TSequence;
begin
  Result := Derive(TFusion.AppendScan(FStages, Seed, Fn));
end;

function TSequence.FlatMap(const Fn: TSequenceBinder): TSequence;
var
  Binder: TSequenceBinder;
begin
  Binder := Fn;
  Result := Derive(TFusion.AppendFlatMap(FStages,
    function (Value: Variant): TVarSource
    var
      Inner: TSequence;
    begin
      Inner := Binder(Value);
      Result := procedure (const Sink: TVarSink)
        begin
          Inner.Run(Sink);
        end;
    end));
end;

{ Combining sequences }

function TSequence.ZipWith(const Other: TSequence; const Fn: TVarFoldFunc): TSequence;
var
  Outer, Partner: TSequence;
  Combine: TVarFoldFunc;
  NoStages: TFusionStages;
begin
  if not Other.IsBounded then
    raise EFunctional.Create(
      'TSequence.ZipWith: partner must be bounded - use ZipWithList for an infinite partner');
  Outer := Self;
  Partner := Other;
  Combine := Fn;
  // A bounded partner bounds the zip, even when Self is infinite
  Result := TSequence.Create(
    procedure (const Sink: TVarSink)
    var
      Items: TVarArray;
      K: Integer;
    begin
      Items := Partner.ToArray;
      if Length(Items) = 0 then
        exit;
      K := 0;
      Outer.RunUnchecked(function (Value: Variant): Boolean
        begin
          Result := Sink(Combine(Value, Items[K]));
          Inc(K);
          if K > High(Items) then
            Result := False;
        end);
    end,
    'Zip(' + Describe + ', ' + Other.Describe + ')', False, NoStages);
end;

function TSequence.ZipWithList(const List: TLazyList; const Fn: TVarFoldFunc): TSequence;
var
  Outer: TSequence;
  Start: TLazyList;
  Combine: TVarFoldFunc;
  NoStages: TFusionStages;
begin
  Outer := Self;
  Start := List;
  Combine := Fn;
  // The list may be infinite, so only Self's finiteness is known
  Result := TSequence.Create(
    procedure (const Sink: TVarSink)
    var
      Cursor: TLazyList;
    begin
      Cursor := Start;
      if Cursor.IsEmpty then
        exit;
      Outer.RunUnchecked(function (Value: Variant): Boolean
        begin
          Result := Sink(Combine(Value, Cursor.Head));
          Cursor := Cursor.Tail;
          if Cursor.IsEmpty then
            Result := False;
        end);
    end,
    'ZipList(' + Describe + ')', not IsBounded, NoStages);
end;

{ Terminal operations }

function TSequence.Fold(const Seed: Variant; const Fn: TVarFoldFunc): Variant;
var
  Acc: Variant;
  Reducer: TVarFoldFunc;
begin
  Acc := Seed;
  Reducer := Fn;
  Run(function (Value: Variant): Boolean
    begin
      Acc := Reducer(Acc, Value);
      Result := True;
    end);
  Result := Acc;
end;

function TSequence.ToArray: TVarArray;
var
  Items: TVarArray;
begin
  Run(function (Value: Variant): Boolean
    begin
      Items.Add(Value);
      Result := True;
    end);
  Result := Items;
end;

function TSequence.Count: Integer;
var
  Total: Integer;
begin
  Total := 0;
  Run(function (Value: Variant): Boolean
    begin
      Inc(Total);
      Result := True;
    end);
  Result := Total;
end;

function TSequence.AsString: String;
var
  Items: TVarArray;
  Text: String;
  i: Integer;
begin
  Items := ToArray;
  Result := '[';
  for i := 0 to High(Items) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Text := Items[i];
    Result := Result + Text;
  end;
  Result := Result + ']';
end;

{ Deferred terminal operations }

function TSequence.FoldLazy(const Seed: Variant; const Fn: TVarFoldFunc): TLazy;
var
  Source: TSequence;
  Start: Variant;
  Reducer: TVarFoldFunc;
begin
  Source := Self;
  Start := Seed;
  Reducer := Fn;
  Result := TLazy.Create(
    function: Variant
    begin
      Result := Source.Fold(Start, Reducer);
    end);
end;

function TSequence.Head: TLazy;
var
  Source: TSequence;
begin
  Source := Self.Take(1);
  Result := TLazy.Create(
    function: Variant
    var
      Items: TVarArray;
    begin
      Items := Source.ToArray;
      if Length(Items) = 0 then
        raise EFunctional.Create('TSequence.Head: sequence is empty');
      Result := Items[0];
    end);
end;

{ Introspection }

function TSequence.Describe: String;
begin
  Result := FSourceName;
  if Length(FStages) > 0 then
    Result := Result + ' -> ' + TFusion.Describe(FStages);
end;

function TSequence.StageCount: Integer;
begin
  Result := Length(FStages);
end;

end.
