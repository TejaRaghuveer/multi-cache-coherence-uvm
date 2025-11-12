param(
  [ValidateSet("questa","vcs","xcelium")]
  [string]$simTool = "questa",
  [string]$projRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path),
  [string]$workDir  = "..\sim",
  [switch]$clean = $false,
  [string]$top    = "top_tb",
  [string]$uvmTest = "cache_test",
  [int]$runs = 5,
  [string]$defaultSeq = "coh_full_transition_vseq"
)

$srcFiles = @(
  "$projRoot\..\uvm_tb\cache_if.sv",
  "$projRoot\..\uvm_tb\cache_state_pkg.sv",
  "$projRoot\..\models\cache_model_pkg.sv",
  "$projRoot\..\models\functional_cache_model.sv",
  "$projRoot\..\models\cache_model_mgr.sv",
  "$projRoot\..\uvm_tb\cache_pkg.sv",
  "$projRoot\..\uvm_tb\cache_env_test.sv",
  "$projRoot\..\uvm_tb\top_tb.sv"
)

$tests = @(
  @{ name="default";    seq=""; },
  @{ name="state_walk"; seq="coh_state_walk_seq"; },
  @{ name="upgrade";    seq="coh_upgrade_seq"; },
  @{ name="conflict";   seq="coh_conflict_seq"; },
  @{ name="random";     seq="coh_random_seq"; }
)

if ($clean -and (Test-Path $workDir)) { Remove-Item $workDir -Recurse -Force }
New-Item $workDir -ItemType Directory -Force | Out-Null
Set-Location $workDir

switch ($simTool) {
  "questa" {
    $toolRoot = $env:QUESTA_HOME
    $vlib   = Join-Path $toolRoot "win64\vlib.exe"
    $vmap   = Join-Path $toolRoot "win64\vmap.exe"
    $vlog   = Join-Path $toolRoot "win64\vlog.exe"
    $vsim   = Join-Path $toolRoot "win64\vsim.exe"
    $vcover = Join-Path $toolRoot "win64\vcover.exe"

    & $vlib work
    & $vmap work work

    $vlogArgs = "-sv +acc +cover=bcesf " + ($srcFiles -join " ")
    & $vlog $vlogArgs

    foreach ($test in $tests) {
      for ($i = 0; $i -lt $runs; $i++) {
        $seed = Get-Random -Minimum 1 -Maximum 4294967295
        $label = "{0}_{1}" -f $test.name, $seed
        $plusSeq = ($test.seq -ne "") ? "+COH_SEQ=$($test.seq)" : "+COH_SEQ=$defaultSeq"
        $logDir = Join-Path $workDir $label
        New-Item $logDir -ItemType Directory -Force | Out-Null

        $vsimArgs = @(
          "-c", $top,
          "-coverage",
          "-do", "run -all; quit -code [coverage attribute -name TESTSTATUS];",
          "+UVM_TESTNAME=$uvmTest",
          "+ntb_random_seed=$seed",
          $plusSeq
        )

        Write-Host "Running $label ..."
        & $vsim $vsimArgs 2>&1 | Tee-Object -FilePath (Join-Path $logDir "vsim.log")

        Get-ChildItem -Filter "cache_trace*.log" | ForEach-Object {
          $zipName = $_.FullName + ".zip"
          Compress-Archive -Path $_.FullName -DestinationPath $zipName -Force
          Remove-Item $_.FullName
        }
      }
    }

    $ucdb = Get-ChildItem -Path $workDir -Filter "*.ucdb" -Recurse
    if ($ucdb.Count -gt 0) {
      $mergeArgs = @("merge","regression.ucdb") + ($ucdb | ForEach-Object { $_.FullName })
      & $vcover $mergeArgs
      & $vcover "report","regression.ucdb","-details","-output","coverage_report.txt"
    } else {
      Write-Warning "No UCDB files found."
    }
  }
  "vcs" {
    $compile = "vcs -full64 -sverilog +acc +cover=bcesf -ntb_opts uvm -l compile.log " + ($srcFiles -join " ") + " -top $top"
    Invoke-Expression $compile

    foreach ($test in $tests) {
      for ($i = 0; $i -lt $runs; $i++) {
        $seed = Get-Random
        $label = "{0}_{1}" -f $test.name, $seed
        $plusSeq = ($test.seq -ne "") ? "+COH_SEQ=$($test.seq)" : "+COH_SEQ=$defaultSeq"
        $logDir = Join-Path $workDir $label
        New-Item $logDir -ItemType Directory -Force | Out-Null

        $simCmd = "./simv -l $($logDir)\sim.log +UVM_TESTNAME=$uvmTest +ntb_random_seed=$seed $plusSeq -cm line+cond+fsm+tgl"
        Invoke-Expression $simCmd

        Get-ChildItem -Filter "cache_trace*.log" | ForEach-Object {
          $zipName = $_.FullName + ".zip"
          Compress-Archive -Path $_.FullName -DestinationPath $zipName -Force
          Remove-Item $_.FullName
        }
      }
    }

    $covDirs = Get-ChildItem -Directory -Filter "urgReport*" -Recurse
    if ($covDirs.Count -gt 0) {
      $merge = "urg -dir " + ($covDirs | ForEach-Object { $_.FullName } -join ",") + " -report coverage_report"
      Invoke-Expression $merge
      if (Test-Path "coverage_report\urgReport") {
        Compress-Archive -Path "coverage_report\urgReport" -DestinationPath "coverage_report.zip" -Force
      }
    }
  }
  "xcelium" {
    foreach ($test in $tests) {
      for ($i = 0; $i -lt $runs; $i++) {
        $seed = Get-Random
        $label = "{0}_{1}" -f $test.name, $seed
        $plusSeq = ($test.seq -ne "") ? "+COH_SEQ=$($test.seq)" : "+COH_SEQ=$defaultSeq"
        $logDir = Join-Path $workDir $label
        New-Item $logDir -ItemType Directory -Force | Out-Null

        $irun = "irun -64bit -uvm -access +rwc -coverage functional -covoverwrite -top $top " +
                ($srcFiles | ForEach-Object { " -f $_" }) -join "" +
                " +UVM_TESTNAME=$uvmTest +ntb_random_seed=$seed $plusSeq -log $($logDir)\irun.log"
        Invoke-Expression $irun

        Get-ChildItem -Filter "cache_trace*.log" | ForEach-Object {
          $zipName = $_.FullName + ".zip"
          Compress-Archive -Path $_.FullName -DestinationPath $zipName -Force
          Remove-Item $_.FullName
        }
      }
    }

    $covReport = "imc -exec \"db merge -o regression; report -stdout -detail -o coverage_report.txt\""
    Invoke-Expression $covReport
  }
}

Write-Host ("Regression complete. Coverage report located at {0}" -f (Join-Path $workDir 'coverage_report.txt'))
