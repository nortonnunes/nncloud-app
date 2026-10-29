# Acrescenta ao Runner.xcodeproj o alvo da extensão File Provider (NNCloudFP) e a
# embute no app. Idempotente: rodar de novo não duplica nada.
#
#   L=/opt/homebrew/Cellar/cocoapods/<versão>/libexec
#   GEM_HOME=$L GEM_PATH="$L:$(ruby -e 'print Gem.default_dir')" ruby scripts/adicionar-extensao-fp.rb
#
# A extensão compila os próprios arquivos (macos/NNCloudFP) e os do cliente
# (macos/NNCloudKit/Sources/NNCloudKit) — o mesmo código que `swift test` confere.
require 'xcodeproj'

raiz = File.expand_path('..', __dir__)
proj = Xcodeproj::Project.open(File.join(raiz, 'macos/Runner.xcodeproj'))
runner = proj.targets.find { |t| t.name == 'Runner' } or abort 'alvo Runner não encontrado'

alvo = proj.targets.find { |t| t.name == 'NNCloudFP' }
if alvo.nil?
  alvo = proj.new_target(:app_extension, 'NNCloudFP', :osx, '13.0')
  grupo = proj.main_group.find_subpath('NNCloudFP', true)
  grupo.set_source_tree('SOURCE_ROOT')
  grupo.set_path('NNCloudFP')
  kit = proj.main_group.find_subpath('NNCloudKit', true)
  kit.set_source_tree('SOURCE_ROOT')
  kit.set_path('NNCloudKit/Sources/NNCloudKit')
  arquivos = Dir[File.join(raiz, 'macos/NNCloudFP/*.swift')].sort.map { |f| grupo.new_file(File.basename(f)) } +
             Dir[File.join(raiz, 'macos/NNCloudKit/Sources/NNCloudKit/*.swift')].sort.map { |f| kit.new_file(File.basename(f)) }
  alvo.add_file_references(arquivos)
  grupo.new_file('Info.plist')
  grupo.new_file('NNCloudFP.entitlements')
end

alvo.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_NAME'] = 'NNCloudFP'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = '$(NNCLOUD_ID).fp'
  s['INFOPLIST_FILE'] = 'NNCloudFP/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'NNCloudFP/NNCloudFP.entitlements'
  s['CODE_SIGN_STYLE'] = 'Manual'
  s['CODE_SIGN_IDENTITY'] = '-'          # o scripts/empacotar-macos.sh assina com o Developer ID
  s['DEVELOPMENT_TEAM'] = ''
  s['ENABLE_HARDENED_RUNTIME'] = 'YES'
  s['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  s['SWIFT_VERSION'] = '5.0'
  s['SKIP_INSTALL'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks', '@executable_path/../../../../Frameworks']
end

# A versão (FLUTTER_BUILD_NAME/NUMBER) vem do mesmo xcconfig do Runner — a extensão
# tem de ter a MESMA versão do app, senão o macOS reclama ao carregar.
alvo.build_configurations.each do |c|
  base = runner.build_configurations.find { |r| r.name == c.name }&.base_configuration_reference
  c.base_configuration_reference = base if base
end

# O Runner depende da extensão e a copia para Contents/PlugIns.
runner.add_dependency(alvo) unless runner.dependencies.any? { |d| d.target == alvo }
fase = runner.copy_files_build_phases.find { |f| f.name == 'Embed App Extensions' }
if fase.nil?
  fase = runner.new_copy_files_build_phase('Embed App Extensions')
  fase.dst_subfolder_spec = '13'   # PlugIns
end
unless fase.files_references.include?(alvo.product_reference)
  bf = fase.add_file_reference(alvo.product_reference)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
proj.save
puts 'NNCloudFP pronto no Runner.xcodeproj'
