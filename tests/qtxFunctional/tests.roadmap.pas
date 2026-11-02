unit tests.roadmap;

// ---------------------------------------------------------------------------
//  qtxFunctional - roadmap tests (Stages 1-4)
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.stats,
  functional.eager,
  functional.lazyinteger,
  functional.floats,
  functional.fn,
  functional.lazy,
  functional.lazylist,
  functional.sequence,
  functional.collections;

type
  TCheckProc   = procedure (const Name, Actual, Expected: String);
  TSectionProc = procedure (const Title: String);

procedure RunRoadmapTests(const Check: TCheckProc; const Section: TSectionProc);

implementation

type
  TParticle = class
  public
    X, V: Float;
    constructor Create(PosX, Velocity: Float);
  end;

constructor TParticle.Create(PosX, Velocity: Float);
begin
  X := PosX;
  V := Velocity;
end;

function VarText(const Value: Variant): String;
begin
  Result := Value;
end;

function JoinKeys(const Keys: TStrArray): String;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(Keys) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + Keys[i];
  end;
end;

function Person(const Name: String; Age: Integer): Variant;
var
  Names: TStringArray;
  Values: TVarArray;
begin
  Names.Add('name');
  Names.Add('age');
  Values.Add(Name);
  Values.Add(Age);
  Result := TValueFunction.MakeRecord(Names, Values);
end;

function ElapsedMs(Started: Float): String;
begin
  Result := IntToStr(Round((Now - Started) * 86400000)) + ' ms';
end;

{ Stage 1 }

procedure Stage1(const Check: TCheckProc; const Section: TSectionProc);
var
  Started: Float;
  EagerSum, LazySum: Integer;
  EagerArrays, EagerElements, EagerSource, EagerObjects: Integer;
  EagerTime, LazyTime: String;
begin
  Section('Stage 1 - eager vs lazy: Range(1,100000).Map(sqr).Filter(even).Take(10).Fold(Sum)');

  TFunctionalStats.Reset;
  Started := Now;
  EagerSum := TEagerInteger.Range(1, 100000)
    .Map(TFunction.Square())
    .Filter(TFunction.IsEven())
    .Take(10)
    .Fold(0, TFunction.Sum());
  EagerTime := ElapsedMs(Started);
  EagerArrays := TFunctionalStats.IntermediateArrays;
  EagerElements := TFunctionalStats.ArrayElements;
  EagerSource := TFunctionalStats.SourceElements;
  EagerObjects := TFunctionalStats.PipelineObjects;
  writeln('  info  eager: ' + TFunctionalStats.Report + '  (' + EagerTime + ')');

  TFunctionalStats.Reset;
  Started := Now;
  LazySum := TLazyInteger.Range(1, 100000)
    .Map(TFunction.Square())
    .Filter(TFunction.IsEven())
    .Take(10)
    .Fold(0, TFunction.Sum());
  LazyTime := ElapsedMs(Started);
  writeln('  info  lazy : ' + TFunctionalStats.Report + '  (' + LazyTime + ')');

  Check('Eager result', IntToStr(EagerSum), '1540');
  Check('Lazy result (identical)', IntToStr(LazySum), '1540');
  Check('Eager intermediate arrays', IntToStr(EagerArrays), '4');
  Check('Eager elements materialised', IntToStr(EagerElements), '250010');
  Check('Eager source elements produced', IntToStr(EagerSource), '100000');
  Check('Lazy intermediate arrays', IntToStr(TFunctionalStats.IntermediateArrays), '0');
  Check('Lazy elements materialised', IntToStr(TFunctionalStats.ArrayElements), '0');
  Check('Lazy source elements produced', IntToStr(TFunctionalStats.SourceElements), '20');
  Check('Pipeline objects (eager / lazy)',
    IntToStr(EagerObjects) + ' / ' + IntToStr(TFunctionalStats.PipelineObjects), '4 / 4');
end;

{ Stage 2 }

procedure Stage2(const Check: TCheckProc; const Section: TSectionProc);
var
  Coeffs: TFloatArray;
  Inc1, Dbl, Composed, Piped: TFn;
  Steps: TFnArray;
  People: TVarArray;
  Ada, Older: Variant;
  Start, Later: TParticle;
  Step: TVarFunc;
begin
  Section('Stage 2 - floats');
  Coeffs.Add(1);
  Coeffs.Add(0);
  Coeffs.Add(2);
  Check('Polynomial 1 + 2x^2 at x=3',
    FloatToStr(TFloatFunction.Polynomial(Coeffs)(3)), '19');
  Check('Compose(Root, Square)(-4)',
    FloatToStr(TFloatFunction.Compose(TFloatFunction.Root(), TFloatFunction.Square())(-4)), '4');
  Check('Range(1,4).Map(*0.5).Fold(Sum)',
    VarText(TSequence.Range(1, 4)
      .Map(TFloatFunction.Lift(TFloatFunction.Scale(0.5)))
      .Fold(0.0, TFloatFunction.LiftFold(TFloatFunction.Sum()))), '5');

  Section('Stage 2 - reusable function wrappers (TFn)');
  Inc1 := TFn.Create('inc', TVarFunction.Lift(TFunction.Add(1)));
  Dbl := TFn.Create('double', TVarFunction.Lift(TFunction.Multiply(2)));
  Composed := TFn.Compose(Inc1, Dbl);
  Check('Compose(inc, double) name', Composed.Name, 'inc . double');
  Check('Compose(inc, double)(5) = inc(double(5))', VarText(Composed.Apply(5)), '11');
  Check('double.AndThen(inc)(5)', VarText(Dbl.AndThen(Inc1).Apply(5)), '11');
  Steps.Add(Inc1);
  Steps.Add(Dbl);
  Steps.Add(Inc1);
  Piped := TFn.Pipeline(Steps);
  Check('Pipeline([inc, double, inc]) name', Piped.Name, 'inc . double . inc');
  Check('Pipeline([inc, double, inc])(5)', VarText(Piped.Apply(5)), '13');
  Check('double iterated 10 times on 1', VarText(Dbl.Iterate(1, 10)), '1024');

  Section('Stage 2 - records and objects');
  Ada := Person('Ada', 36);
  People.Add(Ada);
  People.Add(Person('Alan', 41));
  People.Add(Person('Grace', 29));
  People.Add(Person('Linus', 21));
  Check('People over 30, by name',
    VarText(TSequence.FromArray(People)
      .Filter(TValueFunction.Where('age', TVarFunction.LiftPredicate(TFunction.GreaterThan(30))))
      .Map(TValueFunction.Field('name'))
      .Fold('', TVarFunction.Concat(', '))), 'Ada, Alan');
  Older := TValueFunction.UpdateField('age', TVarFunction.Lift(TFunction.Add(1)))(Ada);
  Check('UpdateField returns new record', VarText(TValueFunction.Field('age')(Older)), '37');
  Check('Original record unchanged', VarText(TValueFunction.Field('age')(Ada)), '36');

  Start := TParticle.Create(0, 1.5);
  Step := function (Value: Variant): Variant
    var
      P: TParticle;
    begin
      P := TParticle(TValueFunction.ToObject(Value));
      Result := TValueFunction.FromObject(TParticle.Create(P.X + P.V, P.V));
    end;
  Later := TParticle(TValueFunction.ToObject(
    TSequence.Iterate(TValueFunction.FromObject(Start), Step).Drop(4).Head.Value));
  Check('Particle x after 4 immutable steps', FloatToStr(Later.X), '6');
  Check('Starting particle untouched', FloatToStr(Start.X), '0');
end;

{ Stage 3 }

procedure Stage3(const Check: TCheckProc; const Section: TSectionProc);
var
  Calls, Ticks, Forced: Integer;
  Cached, Uncached: TLazyValue;
  Ones, Fibs: TLazyList;
  Last: Variant;
begin
  Section('Stage 3 - TLazyValue with optional caching');
  Calls := 0;
  Cached := TLazyValue.Create(
    function: Variant
    begin
      Inc(Calls);
      Result := 6 * 7;
    end);
  VarText(Cached.Value);
  VarText(Cached.Value);
  Check('Memoised value', VarText(Cached.Value), '42');
  Check('Memoised: evaluated once', IntToStr(Cached.EvaluationCount), '1');

  Ticks := 0;
  Uncached := TLazyValue.Create(
    function: Variant
    begin
      Inc(Ticks);
      Result := Ticks;
    end, False);
  VarText(Uncached.Value);
  VarText(Uncached.Value);
  Last := Uncached.Value;
  Check('Uncached: recomputed on each read', VarText(Last), '3');
  Check('Uncached: evaluation count', IntToStr(Uncached.EvaluationCount), '3');
  Check('Uncached: never holds a cached value', BoolToStr(Uncached.IsEvaluated), BoolToStr(False));

  Section('Stage 3 - recursive and infinite lazy lists');
  Ones := TLazyList.Cons(1,
    function: TLazyList
    begin
      Result := Ones;
    end);
  Check('Ones = Cons(1, Ones) .Take(5)', Ones.Take(5).AsString, '[1, 1, 1, 1, 1]');

  Check('Naturals.Map(sqr).Filter(odd).Take(5)',
    TLazyList.Iterate(0, TVarFunction.Lift(TFunction.Add(1)))
      .Map(TVarFunction.Lift(TFunction.Square()))
      .Filter(TVarFunction.LiftPredicate(TFunction.IsOdd()))
      .Take(5).AsString,
    '[1, 9, 25, 49, 81]');

  Fibs := TLazyList.Cons(0,
    function: TLazyList
    begin
      Result := TLazyList.Cons(1,
        function: TLazyList
        begin
          Result := TLazyList.ZipWith(Fibs, Fibs.Tail,
            TVarFunction.LiftFold(TFunction.Sum()));
        end);
    end);
  Check('Self-referential Fibs.Take(10)', Fibs.Take(10).AsString,
    '[0, 1, 1, 2, 3, 5, 8, 13, 21, 34]');

  TLazyList.ForcedTails := 0;
  Check('Fibs.Nth(30)', VarText(Fibs.Nth(30)), '832040');
  Forced := TLazyList.ForcedTails;
  writeln('  info  tails forced for Nth(30): ' + IntToStr(Forced) +
    '  (naive recursion would make ~2.7 million calls)');
  Check('Memoisation keeps it linear (forced tails <= 60)', BoolToStr(Forced <= 60), BoolToStr(True));
  VarText(Fibs.Nth(30));
  Check('Second Nth(30) forces nothing new', IntToStr(TLazyList.ForcedTails - Forced), '0');
end;

{ Stage 4 }

procedure Stage4(const Check: TCheckProc; const Section: TSectionProc);
var
  L1, L2, L3, B: TImmutableList;
  Cells, Before: Integer;
  V1, V2, V3: TPersistentMap;
begin
  Section('Stage 4 - immutable list with structural sharing');
  L1 := TImmutableList.FromArray(TSequence.Range(1, 3).ToArray);
  Cells := TImmutableList.CellsCreated;
  L2 := L1.Cons(0);
  Check('L2 := L1.Cons(0)', L2.AsString, '[0, 1, 2, 3]');
  Check('L1 unchanged', L1.AsString, '[1, 2, 3]');
  Check('L2.Tail is physically L1', BoolToStr(L2.Tail = L1), BoolToStr(True));
  Check('Cells allocated by Cons', IntToStr(TImmutableList.CellsCreated - Cells), '1');

  L3 := L2.SetNth(1, 99);
  Check('L3 := L2.SetNth(1, 99)', L3.AsString, '[0, 99, 2, 3]');
  Check('L2 unchanged', L2.AsString, '[0, 1, 2, 3]');
  Check('L3 shares the suffix after the change', BoolToStr(L3.Tail.Tail = L2.Tail.Tail), BoolToStr(True));

  B := TImmutableList.FromArray(TSequence.Range(7, 8).ToArray);
  Check('L1.Append(B)', L1.Append(B).AsString, '[1, 2, 3, 7, 8]');
  Check('Append shares all of B', BoolToStr(L1.Append(B).Tail.Tail.Tail = B), BoolToStr(True));
  Check('Reverse', L2.Reverse.AsString, '[3, 2, 1, 0]');
  Check('Fold(Sum)', VarText(L2.Fold(0, TVarFunction.LiftFold(TFunction.Sum()))), '6');
  Check('List into a fused pipeline',
    L1.ToSequence.Map(TVarFunction.Lift(TFunction.Multiply(10))).AsString, '[10, 20, 30]');

  Section('Stage 4 - persistent map (path copying)');
  V1 := TPersistentMap.Empty
    .Put('m', 'mango').Put('c', 'cherry').Put('t', 'tomato')
    .Put('a', 'apple').Put('e', 'egg').Put('p', 'pear').Put('z', 'zucchini');
  Check('V1 keys in order', JoinKeys(V1.Keys), 'a, c, e, m, p, t, z');
  Check('V1 height', IntToStr(V1.Height), '3');

  Before := TPersistentMap.NodesCreated;
  V2 := V1.Put('e', 'eggplant');
  Check('Nodes copied to update e (its path)', IntToStr(TPersistentMap.NodesCreated - Before), '3');
  Check('Nodes shared by V1 and V2', IntToStr(V1.SharedNodes(V2)), '4');
  Check('V1.Get(e) - old version intact', VarText(V1.Get('e')), 'egg');
  Check('V2.Get(e)', VarText(V2.Get('e')), 'eggplant');

  Before := TPersistentMap.NodesCreated;
  V3 := V2.Remove('c');
  Check('Nodes created to remove c', IntToStr(TPersistentMap.NodesCreated - Before), '2');
  Check('V3', V3.AsString, '{a: apple, e: eggplant, m: mango, p: pear, t: tomato, z: zucchini}');
  Check('V2 still contains c', BoolToStr(V2.ContainsKey('c')), BoolToStr(True));
  Check('Counts V1 / V2 / V3',
    IntToStr(V1.Count) + ' / ' + IntToStr(V2.Count) + ' / ' + IntToStr(V3.Count), '7 / 7 / 6');
  Check('Nodes shared by V2 and V3', IntToStr(V2.SharedNodes(V3)), '4');

  try
    V3.Get('c');
    Check('Get of removed key raises', 'no error', 'EFunctional');
  except
    on E: EFunctional do
      Check('Get of removed key raises', 'EFunctional', 'EFunctional');
  end;
end;

procedure RunRoadmapTests(const Check: TCheckProc; const Section: TSectionProc);
begin
  Stage1(Check, Section);
  Stage2(Check, Section);
  Stage3(Check, Section);
  Stage4(Check, Section);
end;

end.
