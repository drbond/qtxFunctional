unit graph.scenarios;

// ---------------------------------------------------------------------------
//  qtxFunctionGraph - preset graphs
//
//  Each scenario builds a TFunctionGraph from named functions. Nothing runs
//  while a graph is being built - it is only a description of the work.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.sequence,
  functional.graph;

const
  ScenarioCount = 7;

type
  TScenarios = class
  public
    class function Title(Index: Integer): String;
    class function Description(Index: Integer): String;
    class function Build(Index: Integer): TFunctionGraph;
  end;

implementation

function Square: TVarFunc;
begin
  Result := TVarFunction.Lift(TFunction.Square());
end;

function AddOne: TVarFunc;
begin
  Result := TVarFunction.Lift(TFunction.Add(1));
end;

function Triple: TVarFunc;
begin
  Result := TVarFunction.Lift(TFunction.Multiply(3));
end;

function EvenTest: TVarPredicate;
begin
  Result := TVarFunction.LiftPredicate(TFunction.IsEven());
end;

function OddTest: TVarPredicate;
begin
  Result := TVarFunction.LiftPredicate(TFunction.IsOdd());
end;

function Prime: TVarPredicate;
begin
  Result := function (Value: Variant): Boolean
    var
      N, d: Integer;
    begin
      N := Value;
      if N < 2 then
        exit(False);
      d := 2;
      while d * d <= N do
      begin
        if (N mod d) = 0 then
          exit(False);
        Inc(d);
      end;
      Result := True;
    end;
end;

function Sum: TVarFoldFunc;
begin
  Result := TVarFunction.LiftFold(TFunction.Sum());
end;

function Count: TVarFoldFunc;
begin
  Result := function (Accumulator, Value: Variant): Variant
    var
      A: Integer;
    begin
      A := Accumulator;
      Result := A + 1;
    end;
end;

class function TScenarios.Title(Index: Integer): String;
begin
  case Index of
    0: Result := 'The pipeline from the notes: Map, Map, Filter';
    1: Result := 'Two outputs, one pass: sum and count of the evens';
    2: Result := 'Duplicate work in two branches';
    3: Result := 'A shared step blocks fusion';
    4: Result := 'Redundant steps';
    5: Result := 'Infinite source, three outputs, early stop';
    6: Result := 'An output that would never finish';
  else
    Result := '';
  end;
end;

class function TScenarios.Description(Index: Integer): String;
begin
  case Index of
    0: Result := 'Input sequence, Map(F), Map(G), Filter(P). The optimiser composes the two ' +
         'functions into one Map, so each value passes through two steps instead of three.';
    1: Result := 'One filtered stream feeds two Folds. Executed as a graph, the source is read ' +
         'once and every value fans out to both outputs; run separately, it is read twice.';
    2: Result := 'Two branches each compute Map square from the same source, written as two ' +
         'separate nodes. The optimiser spots they are the same work and shares one node.';
    3: Result := 'Map triple feeds two consumers. Fusing it into Map add 1 would mean running ' +
         'it twice, so the optimiser leaves it alone and says why.';
    4: Result := 'An identity Map, two Drops in a row, and a Map just before a Fold. The ' +
         'optimiser removes, merges and moves them - the result does not change.';
    5: Result := 'Primes from the infinite natural numbers feed three outputs. The graph keeps ' +
         'reading the source only until the last output is satisfied, then stops.';
    6: Result := 'An infinite source with no Take. Because the graph can be inspected before ' +
         'it runs, the engine refuses to execute it instead of looping forever.';
  else
    Result := '';
  end;
end;

class function TScenarios.Build(Index: Integer): TFunctionGraph;
var
  Src, Evens, Sq, SqA, SqB, Tripled, Primes: TGraphNode;
begin
  TGraphNode.ResetIds;
  Result := TFunctionGraph.Create;
  case Index of
    0:
      begin
        Src := TGraphNode.Source('range 1..10', TSequence.Range(1, 10));
        Result := Result.Output('result',
          Src.Map('square', Square).Map('add 1', AddOne).Filter('even', EvenTest));
      end;
    1:
      begin
        Src := TGraphNode.Source('range 1..100', TSequence.Range(1, 100));
        Evens := Src.Filter('even', EvenTest);
        Result := Result
          .Output('sum', Evens.Fold('sum', 0, Sum))
          .Output('count', Evens.Fold('count', 0, Count));
      end;
    2:
      begin
        Src := TGraphNode.Source('naturals', TSequence.From(1));
        SqA := Src.Map('square', Square);
        SqB := Src.Map('square', Square);     // written twice on purpose
        Result := Result
          .Output('odd squares', SqA.Filter('odd', OddTest).Take(5))
          .Output('sum of 5 squares', SqB.Take(5).Fold('sum', 0, Sum));
      end;
    3:
      begin
        Src := TGraphNode.Source('range 1..20', TSequence.Range(1, 20));
        Tripled := Src.Map('triple', Triple);
        Result := Result
          .Output('a', Tripled.Map('add 1', AddOne))
          .Output('b', Tripled.Filter('even', EvenTest));
      end;
    4:
      begin
        Src := TGraphNode.Source('naturals', TSequence.From(1));
        Result := Result.Output('result',
          Src.Identity.Take(10).Drop(2).Drop(3).Take(3).Map('square', Square).Fold('sum', 0, Sum));
      end;
    5:
      begin
        Src := TGraphNode.Source('naturals', TSequence.From(1));
        Primes := Src.Filter('prime', Prime);
        Result := Result
          .Output('first 10 primes', Primes.Take(10))
          .Output('100th prime', Primes.Drop(99).Take(1))
          .Output('primes below 100', Primes.Take(25).Fold('count', 0, Count));
      end;
    6:
      begin
        Src := TGraphNode.Source('naturals', TSequence.From(1));
        Sq := Src.Map('square', Square);
        Result := Result.Output('all squares', Sq);
      end;
  end;
end;

end.
