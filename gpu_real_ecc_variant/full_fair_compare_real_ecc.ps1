param(
  [int[]]$Sizes = @(128, 256, 512),
  [int]$GpuRepeats = 10,
  [string]$BoostInclude = "C:\cudaimp\third_party\boost_1_87_0",
  [string]$CgbnInclude = "C:\cudaimp\CGBN-master\CGBN-master\include",
  [string]$OutCsv = ".\gpu_real_ecc_variant\full_fair_compare_results.csv"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$cpuSrc = Join-Path $repoRoot "gpu_real_ecc_variant\real_ecc_cpu.cpp"
$gpuSrc = Join-Path $repoRoot "gpu_real_ecc_variant\real_ecc_gpu_verify_kernel.cu"
$cpuExe = Join-Path $repoRoot "gpu_real_ecc_variant\real_ecc_cpu.exe"
$gpuExe = Join-Path $repoRoot "gpu_real_ecc_variant\real_ecc_gpu_verify_kernel.exe"

Write-Host "=== Building Real-ECC CPU reference ===" -ForegroundColor Cyan
& g++ -O2 -std=c++17 "-I$BoostInclude" $cpuSrc -o $cpuExe
if ($LASTEXITCODE -ne 0) { throw "CPU build failed." }

Write-Host "=== Building Real-ECC GPU kernel ===" -ForegroundColor Cyan
& nvcc -O2 -std=c++17 -DXMP_WMAD "-I$CgbnInclude" $gpuSrc -o $gpuExe
if ($LASTEXITCODE -ne 0) { throw "GPU build failed." }

$rows = @()
foreach ($n in $Sizes) {
  Write-Host "`n=== Running N=$n ===" -ForegroundColor Yellow

  $cpuText = (& $cpuExe $n 2>&1 | Out-String)
  $gpuText = (& $gpuExe $n $GpuRepeats 2>&1 | Out-String)

  $cpuMs = [double]([regex]::Match($cpuText, "Verify time \(ms\):\s*([0-9eE\+\.-]+)").Groups[1].Value)
  $cpuThr = [double]([regex]::Match($cpuText, "Throughput \(verifies/s\):\s*([0-9eE\+\.-]+)").Groups[1].Value)
  $cpuValid = [int]([regex]::Match($cpuText, "Valid packets:\s*([0-9]+)").Groups[1].Value)
  $cpuInvalid = [int]([regex]::Match($cpuText, "Invalid packets:\s*([0-9]+)").Groups[1].Value)

  $gpuKernelMs = [double]([regex]::Match($gpuText, "Kernel avg time \(ms\):\s*([0-9eE\+\.-]+)").Groups[1].Value)
  $gpuThr = [double]([regex]::Match($gpuText, "Throughput \(verifies/s\):\s*([0-9eE\+\.-]+)").Groups[1].Value)
  $gpuValid = [int]([regex]::Match($gpuText, "Valid:\s*([0-9]+)").Groups[1].Value)
  $gpuInvalid = [int]([regex]::Match($gpuText, "Invalid:\s*([0-9]+)").Groups[1].Value)
  $gpuMismatch = [int]([regex]::Match($gpuText, "Mismatches vs expected:\s*([0-9]+)").Groups[1].Value)

  $speedupThr = if ($cpuThr -gt 0) { $gpuThr / $cpuThr } else { 0.0 }
  $speedupMs = if ($gpuKernelMs -gt 0) { $cpuMs / $gpuKernelMs } else { 0.0 }
  $validityMatch = (($cpuValid -eq $gpuValid) -and ($cpuInvalid -eq $gpuInvalid))

  $rows += [pscustomobject]@{
    N = $n
    CPU_ms = [math]::Round($cpuMs, 3)
    GPU_kernel_ms = [math]::Round($gpuKernelMs, 3)
    CPU_verifies_s = [math]::Round($cpuThr, 3)
    GPU_verifies_s = [math]::Round($gpuThr, 3)
    Speedup_x_throughput = [math]::Round($speedupThr, 3)
    Speedup_x_time = [math]::Round($speedupMs, 3)
    CPU_valid = $cpuValid
    CPU_invalid = $cpuInvalid
    GPU_valid = $gpuValid
    GPU_invalid = $gpuInvalid
    GPU_mismatch = $gpuMismatch
    Validity_match = $validityMatch
  }
}

Write-Host "`n=== Full Fair Compare Summary ===" -ForegroundColor Green
$rows | Format-Table -AutoSize

$outPath = Resolve-Path (Split-Path $OutCsv -Parent) -ErrorAction SilentlyContinue
if (-not $outPath) {
  New-Item -ItemType Directory -Path (Split-Path $OutCsv -Parent) -Force | Out-Null
}
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutCsv
Write-Host "`nSaved CSV: $OutCsv" -ForegroundColor Cyan
