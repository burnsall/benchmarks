# Builds (if needed) and launches the real VUU server (BenchmarkMain) that
# backs the "vuu" and "ag-grid-vuu" benchmark variants.
#
# Two steps:
#   1. Build+install org.finos.vuu:vuu from the vendor/vuu submodule, using
#      its own Maven Wrapper (vendor/vuu/mvnw.cmd) - the wrapper bootstraps
#      the correct Maven version itself, so the only prerequisite is a JVM
#      on PATH. This is the one dependency BenchmarkMain actually needs from
#      vuu itself (see server/pom.xml) - no PR/branch-specific vuu checkout
#      required, main is enough.
#   2. Build and run this repo's own server/ module (BenchmarkMain.scala,
#      BenchmarkPriceModule.scala etc.) against that locally-installed vuu
#      artifact, using the same Maven Wrapper (-f server/pom.xml).

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")                   # benchmarks/
$vuuSubmoduleDir = Join-Path $repoRoot "vendor\vuu"
$serverModuleDir = Join-Path $repoRoot "server"
$mvn = Join-Path $vuuSubmoduleDir "mvnw.cmd"
$classpathFile = Join-Path $scriptDir "main-classpath.txt"

# -Djavax.net.ssl.trustStoreType=Windows-ROOT: on a machine where HTTPS
# traffic is intercepted for inspection (a corporate proxy or antivirus doing
# TLS inspection, common on managed Windows machines), the JVM's own bundled
# trust store won't trust the intercepting certificate even though Windows
# itself does - which is why a browser or npm works fine but a plain mvn
# call can fail TLS validation when downloading dependencies. Pointing the
# JVM at the Windows certificate store directly (the same store the browser
# and npm already trust) fixes this generically, with no certificate
# export/import and no change to anyone's antivirus/proxy configuration
# required.
$env:MAVEN_OPTS = "-Djavax.net.ssl.trustStoreType=Windows-ROOT"

Push-Location $vuuSubmoduleDir
try {
    Write-Host "[start-vuu-server] building and installing org.finos.vuu:vuu..."
    & $mvn install -pl vuu -am -DskipTests -B -q
    if ($LASTEXITCODE -ne 0) { throw "mvn install (vuu) failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}

Push-Location $serverModuleDir
try {
    $serverPomFile = Join-Path $serverModuleDir "pom.xml"
    if (-not (Test-Path $classpathFile) -or (Get-Item $classpathFile).LastWriteTime -lt (Get-Item $serverPomFile).LastWriteTime) {
        Write-Host "[start-vuu-server] building server module and its runtime classpath..."
        & $mvn install -DskipTests -B -q
        if ($LASTEXITCODE -ne 0) { throw "mvn install (server) failed with exit code $LASTEXITCODE" }
        & $mvn dependency:build-classpath "-Dmdep.outputFile=$classpathFile" -q
        if ($LASTEXITCODE -ne 0) { throw "mvn dependency:build-classpath failed with exit code $LASTEXITCODE" }
    } else {
        & $mvn compile -q
        if ($LASTEXITCODE -ne 0) { throw "mvn compile (server) failed with exit code $LASTEXITCODE" }
    }
    # .Trim() matters: the classpath file (written by mvn dependency:build-classpath)
    # ends in a trailing newline, which otherwise corrupts the multi-line java
    # invocation below (arguments after it get mis-parsed).
    $classpath = (Get-Content $classpathFile -Raw).Trim()

    Write-Host "[start-vuu-server] starting BenchmarkMain on ws://localhost:8090/websocket ..."
    # The -D flag must be quoted: the Oracle "javapath" redirector shim that
    # `java` resolves to on this PATH mis-parses an unquoted -Dkey.sub=value
    # argument (drops the "-Dkey" portion and passes only ".sub=value" through,
    # which java then tries to load as the main class).
    & java -Xmx4096m `
        -classpath "target\classes;$classpath" `
        "-Dlogback.configurationFile=logback-netty.xml" `
        org.finos.vuu.BenchmarkMain
} finally {
    Pop-Location
}
