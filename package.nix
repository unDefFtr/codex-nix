{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
  libcap,
  openssl,
}:

let
  version = "0.151.0";
  repo = "openai/codex";

  platformMap = {
    "x86_64-linux" = "x86_64-unknown-linux-musl";
    "aarch64-linux" = "aarch64-unknown-linux-musl";
    "x86_64-darwin" = "x86_64-apple-darwin";
    "aarch64-darwin" = "aarch64-apple-darwin";
  };

  hashes = {
    "x86_64-unknown-linux-musl" = "1xjq01z5n2zixb2axzm6cvxhfx3nj5qmnfpnvvslbii27wc4nnv0";
    "aarch64-unknown-linux-musl" = "1dk9adngv209xlzzizswnipmpl4g5kf546iqd4a1q9jy6ypjpky1";
    "x86_64-apple-darwin" = "0zk53wszp0d6yv78c1gy1w3jk17ps909gq376vdshiir3limppa0";
    "aarch64-apple-darwin" = "0rf94ak2b13i3v3zbmwbj0isniy4xd402cy75flr9lllb73f42b4";
  };

  platform = platformMap.${stdenv.hostPlatform.system}
    or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  isLinux = stdenv.hostPlatform.isLinux;
in

stdenv.mkDerivation {
  pname = "codex";
  inherit version;

  src = fetchurl {
    url = "https://github.com/${repo}/releases/download/rust-v${version}/codex-${platform}.tar.gz";
    sha256 = hashes.${platform};
  };

  sourceRoot = ".";

  nativeBuildInputs = lib.optionals isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals isLinux [
    stdenv.cc.cc.lib
    zlib
    libcap
    openssl
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp codex-${platform} $out/bin/codex
    chmod +x $out/bin/codex

    runHook postInstall
  '';

  dontFixup = !isLinux;

  meta = {
    description = "OpenAI Codex CLI — an AI coding agent for your terminal";
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/${repo}/releases/tag/rust-v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames platformMap;
    mainProgram = "codex";
  };
}
