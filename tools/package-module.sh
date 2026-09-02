set -e
cd ..

cp -r module/ ./build/
rm -rf build/module/bin/.gitkeep
cp -r tmp/zashboard ./build/module/ui
cp -r build/suclash_helper ./build/module/bin/
cp -r build/MihomoControl.apk ./build/module/bin/
cp -r build/mihomo ./build/module/bin/

zip -r build/module.zip build/module

echo "📦 模块打包完成，产物路径: build/module.zip"