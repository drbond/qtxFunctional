unit functional.neural;

// ---------------------------------------------------------------------------
//  qtxFunctional - an immutable neural network  (Stage 6)
//
//  TNetwork is a 2-input, H-hidden, 1-output multilayer perceptron with
//  sigmoid activations. All its weights live in ONE immutable TVector:
//
//      [ W1 (2H) | B1 (H) | W2 (H) | B2 (1) ]
//
//  Training is expressed functionally:
//    * Gradient(sample) is a pure function returning a gradient vector;
//    * an epoch maps every sample to its gradient, folds them with Add,
//      and returns a NEW network  Params - Rate * (Total / N);
//    * Train runs  TSequence.Iterate(Network, Epoch).Drop(Epochs).Head  -
//      the training history is an infinite lazy sequence of networks.
//
//  Initial weights come from a Park-Miller generator, so runs are
//  reproducible and can be checked against the conventional version.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.floats,
  functional.fn,
  functional.lazy,
  functional.sequence,
  functional.vector;

type
  TSample = record
    X1: Float;
    X2: Float;
    Y:  Float;
  end;

  TSampleArray = array of TSample;

  TNetwork = class
  private
    FHidden: Integer;
    FParams: TVector;
  public
    constructor Create(Hidden: Integer; const Params: TVector);

    class function Initial(Hidden, Seed: Integer): TNetwork;
    class function InitialWeights(Hidden, Seed: Integer): TFloatArray;
    class function XorSamples: TSampleArray;

    function Predict(X1, X2: Float): Float;
    function Gradient(const Sample: TSample): TVector;
    function TrainEpoch(const Samples: TSampleArray; Rate: Float): TNetwork;
    function Train(const Samples: TSampleArray; Rate: Float; Epochs: Integer): TNetwork;
    function Loss(const Samples: TSampleArray): Float;

    property Hidden: Integer read FHidden;
    property Params: TVector read FParams;
  end;

function Sigmoid(Z: Float): Float;

implementation

function Sigmoid(Z: Float): Float;
begin
  Result := 1 / (1 + Exp(-Z));
end;

constructor TNetwork.Create(Hidden: Integer; const Params: TVector);
begin
  FHidden := Hidden;
  FParams := Params;
end;

class function TNetwork.InitialWeights(Hidden, Seed: Integer): TFloatArray;
var
  S: Float;
  i: Integer;
begin
  // Park-Miller minimal standard generator, kept in Float arithmetic so the
  // products stay exact in JavaScript's 53-bit number space
  S := Seed;
  for i := 1 to 4 * Hidden + 1 do
  begin
    S := S * 16807;
    S := S - Trunc(S / 2147483647) * 2147483647;
    Result.Add((S / 2147483647) * 2 - 1);
  end;
end;

class function TNetwork.Initial(Hidden, Seed: Integer): TNetwork;
begin
  Result := TNetwork.Create(Hidden, TVector.Create(InitialWeights(Hidden, Seed)));
end;

class function TNetwork.XorSamples: TSampleArray;

  procedure AddSample(X1, X2, Y: Float);
  var
    S: TSample;
  begin
    S.X1 := X1;
    S.X2 := X2;
    S.Y := Y;
    Result.Add(S);
  end;

begin
  AddSample(0, 0, 0);
  AddSample(0, 1, 1);
  AddSample(1, 0, 1);
  AddSample(1, 1, 0);
end;

function TNetwork.Predict(X1, X2: Float): Float;
var
  j, H: Integer;
  Z, Hj: Float;
begin
  H := FHidden;
  Z := 0;
  for j := 0 to H - 1 do
  begin
    Hj := Sigmoid(FParams.Get(2 * j) * X1 + FParams.Get(2 * j + 1) * X2 + FParams.Get(2 * H + j));
    Z := Z + FParams.Get(3 * H + j) * Hj;
  end;
  Result := Sigmoid(Z + FParams.Get(4 * H));
end;

function TNetwork.Gradient(const Sample: TSample): TVector;
var
  H, j: Integer;
  Act: TFloatArray;
  G: TFloatArray;
  Z, O, DeltaO, DeltaH: Float;
begin
  // A pure function of (network, sample): the local arrays never escape
  H := FHidden;
  Z := 0;
  for j := 0 to H - 1 do
  begin
    Act.Add(Sigmoid(FParams.Get(2 * j) * Sample.X1 +
                    FParams.Get(2 * j + 1) * Sample.X2 +
                    FParams.Get(2 * H + j)));
    Z := Z + FParams.Get(3 * H + j) * Act[j];
  end;
  O := Sigmoid(Z + FParams.Get(4 * H));
  DeltaO := (O - Sample.Y) * O * (1 - O);

  for j := 0 to 4 * H do
    G.Add(0);
  for j := 0 to H - 1 do
  begin
    G[3 * H + j] := DeltaO * Act[j];
    DeltaH := DeltaO * FParams.Get(3 * H + j) * Act[j] * (1 - Act[j]);
    G[2 * j] := DeltaH * Sample.X1;
    G[2 * j + 1] := DeltaH * Sample.X2;
    G[2 * H + j] := DeltaH;
  end;
  G[4 * H] := DeltaO;
  Result := TVector.Create(G);
end;

function TNetwork.TrainEpoch(const Samples: TSampleArray; Rate: Float): TNetwork;
var
  Total: TVector;
  N: Float;
  LearningRate: Float;
  i: Integer;
begin
  // Map each sample to its gradient and fold them together
  Total := TVector.Zeros(FParams.Size);
  for i := 0 to High(Samples) do
    Total := Total.Add(Gradient(Samples[i]));

  N := Length(Samples);
  LearningRate := Rate;
  Result := TNetwork.Create(FHidden, FParams.ZipWith(Total,
    function (W, G: Float): Float
    begin
      Result := W - LearningRate * (G / N);
    end));
end;

function TNetwork.Train(const Samples: TSampleArray; Rate: Float;
  Epochs: Integer): TNetwork;
var
  Data: TSampleArray;
  LearningRate: Float;
  Final: Variant;
begin
  Data := Samples;
  LearningRate := Rate;
  Final := TSequence.Iterate(TValueFunction.FromObject(Self),
    function (Value: Variant): Variant
    var
      Net: TNetwork;
    begin
      Net := TNetwork(TValueFunction.ToObject(Value));
      Result := TValueFunction.FromObject(Net.TrainEpoch(Data, LearningRate));
    end).Drop(Epochs).Head.Value;
  Result := TNetwork(TValueFunction.ToObject(Final));
end;

function TNetwork.Loss(const Samples: TSampleArray): Float;
var
  i: Integer;
  D: Float;
begin
  Result := 0;
  for i := 0 to High(Samples) do
  begin
    D := Predict(Samples[i].X1, Samples[i].X2) - Samples[i].Y;
    Result := Result + D * D;
  end;
  Result := Result / Length(Samples);
end;

end.
