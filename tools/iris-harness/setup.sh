#!/bin/bash
# Rebuilds ~/.solstice-dev/iris-harness (used by tools/iris_check.sh).
# Needs: brew install openjdk. Uses the Iris + Sodium jars from the Lunar profile.
set -e
H="$HOME/.solstice-dev/iris-harness"; P="${SOLSTICE_PROFILE:-$HOME/.lunarclient/profiles/fullbright-4}"
JDK=/opt/homebrew/opt/openjdk/bin
mkdir -p "$H/lib" "$H/stub/META-INF/services"
IRIS=$(ls "$P"/mods/iris-fabric-*.jar | head -1); SODIUM=$(ls "$P"/mods/sodium-fabric-*.jar | head -1)
cp "$IRIS" "$H/lib/iris.jar"; cp "$SODIUM" "$H/lib/sodium.jar"
unzip -o -q -j "$IRIS" 'META-INF/jars/*.jar' -d "$H/lib"; unzip -o -q -j "$SODIUM" 'META-INF/jars/*.jar' -d "$H/lib" || true
cp "$(ls "$HOME/Library/Application Support/minecraft/libraries/net/fabricmc/fabric-loader/"*/fabric-loader-*.jar | tail -1)" "$H/lib/" || true
echo "$H/lib/*:$(find "$HOME/.lunarclient/shared/libraries" -name '*.jar' | tr '\n' ':')$HOME/.lunarclient/shared/versions/26.1.2/26.1.2.jar" > "$H/cp.txt"
cp "$(dirname "$0")"/*.java "$H/"
echo "StubPlatform" > "$H/stub/META-INF/services/net.irisshaders.iris.platform.IrisPlatformHelpers"
cd "$H"; CP="$(cat cp.txt):."
"$JDK/javac" -cp "$CP" -d stub StubPlatform.java
"$JDK/javac" -cp "stub:$CP" -d . Harness.java Keys.java
echo "iris harness ready in $H"
