#!/bin/bash
# ビルド済み WanMap.app の中身をダンプする診断スクリプト（CI専用）。
# project.yml の resources に列挙したファイル（facilities.json /
# Assets.xcassets / Sounds/completion.wav / husky-face.png 等）が
# 実際にアプリバンドルへ入っているかを、推測でなく実物で確定させる。
# 呼び出し側のCIステップを止めないよう、常に正常終了する。
set +e
DERIVED=~/Library/Developer/Xcode/DerivedData

dump_app() {
  local label="$1" product_dir="$2"
  echo "===== WanMap.app ($label / $product_dir) ====="
  local app
  app=$(find "$DERIVED" -path "*/$product_dir/WanMap.app" -type d 2>/dev/null | head -n 1)
  if [ -z "$app" ] && [ "$label" = "device" ]; then
    # 実機向けは旧形式の配置も拾う
    app=$(find "$DERIVED" -name "WanMap.app" -type d 2>/dev/null | grep -v iphonesimulator | head -n 1)
  fi
  echo "WanMap.app ($label): ${app:-not found}"
  if [ -n "$app" ]; then
    find "$app" | sort || true
    if [ -f "$app/Assets.car" ]; then
      echo "--- assetutil --info Assets.car (first 200 lines) ---"
      xcrun assetutil --info "$app/Assets.car" 2>/dev/null | head -n 200 || true
    else
      echo "no Assets.car"
    fi
  fi
}

dump_app "device" "Debug-iphoneos"
dump_app "simulator" "Debug-iphonesimulator"
true
