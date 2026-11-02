unit functional.stats;

// ---------------------------------------------------------------------------
//  qtxFunctional - TFunctionalStats
//
//  Global instrumentation counters so eager and lazy pipelines can be
//  compared objectively (Stage 1 of the roadmap).
//
//    PipelineObjects     pipeline objects created (one per Map/Filter/Take...)
//    IntermediateArrays  arrays materialised while evaluating
//    ArrayElements       total elements stored in those arrays
//    SourceElements      elements produced by the source
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils;

type
  TFunctionalStats = class
  public
    class var PipelineObjects:    Integer;
    class var IntermediateArrays: Integer;
    class var ArrayElements:      Integer;
    class var SourceElements:     Integer;

    class procedure Reset;
    class function  Report: String;
  end;

implementation

class procedure TFunctionalStats.Reset;
begin
  PipelineObjects := 0;
  IntermediateArrays := 0;
  ArrayElements := 0;
  SourceElements := 0;
end;

class function TFunctionalStats.Report: String;
begin
  Result :=
    'objects=' + IntToStr(PipelineObjects) +
    ' arrays=' + IntToStr(IntermediateArrays) +
    ' array-elements=' + IntToStr(ArrayElements) +
    ' source-elements=' + IntToStr(SourceElements);
end;

end.
