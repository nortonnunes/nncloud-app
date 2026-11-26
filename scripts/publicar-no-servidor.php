<?php
/*
 * Publica um instalador do APP Operação UNIFI pelo terminal — o MESMO caminho
 * do CallAppConfigController::appConcluir (conferências, Armazenamento, setting,
 * evento), para um arquivo que já está no servidor.
 *
 * Roda NO SERVIDOR, lido pela entrada padrão (o arquivo não precisa estar lá):
 *   scp -i ~/.ssh/macLaercio.pem Conecta-Callcenter-1.2.3.dmg ubuntu@52.67.111.122:/tmp/
 *   ssh -i ~/.ssh/macLaercio.pem ubuntu@52.67.111.122 \
 *     "cd /var/www/noc.nortonnunes.com.br && sudo -u www-data php -- macos 1.2.3 /tmp/Conecta-Callcenter-1.2.3.dmg" \
 *     < scripts/publicar-no-servidor.php
 * <so> = windows | macos | linux. Mesma versão já publicada só é trocada com --forcar.
 */
declare(strict_types=1);

if (PHP_SAPI !== 'cli') { exit(1); }
require getcwd() . '/bootstrap.php';

use App\Core\Armazenamento;
use App\Core\ArquivoRecebido;
use App\Core\CallApp\Config;
use App\Models\CallAppEvento;

$args = array_values(array_filter(array_slice($argv, 1), fn($a) => $a !== '--forcar'));
$forcar = in_array('--forcar', $argv, true);
[$so, $versao, $origem] = $args + ['', '', ''];

function falha(string $m): never { fwrite(STDERR, "ERRO: $m\n"); exit(2); }

if (!isset(Config::SISTEMAS[$so])) falha("sistema inválido ($so)");
if (!Config::versaoValida($versao)) falha("versão inválida ($versao)");
if (!is_file($origem) || !is_readable($origem)) falha("arquivo não encontrado: $origem");

$nomeOrig = basename($origem);
$ext = (string) preg_replace('/[^a-z0-9]+/', '', strtolower(pathinfo($nomeOrig, PATHINFO_EXTENSION)));
if (!in_array($ext, Config::SISTEMAS[$so]['ext'], true)) falha("extensão .$ext não aceita para $so");
if (filesize($origem) > Config::MAX_INSTALADOR) falha('arquivo acima do teto');

$f = fopen($origem, 'rb');
$inicio = (string) fread($f, 8);
$ok = match ($so) {
    'windows' => str_starts_with($inicio, 'MZ'),
    'linux'   => $inicio === "!<arch>\n",
    'macos'   => (filesize($origem) >= 512 && fseek($f, -512, SEEK_END) === 0 && fread($f, 4) === 'koly'),
    default   => false,
};
fclose($f);
if (!$ok) falha('o conteúdo não parece um instalador deste sistema');

$anterior = Config::instalador($so);
if ($anterior !== null && $anterior['versao'] === $versao && !$forcar) {
    echo "Já publicado: $so {$versao} (use --forcar para substituir)\n";
    exit(0);
}

// Copia para o temporário do próprio sistema (mesma partição de storage/):
// o Armazenamento grava por rename.
$tmp = ArquivoRecebido::dirTmp() . '/pub_' . bin2hex(random_bytes(8)) . '.' . $ext;
if (!copy($origem, $tmp)) falha('não consegui copiar para storage/tmp_uploads');
$arq = ArquivoRecebido::deArquivoMontado($tmp, $nomeOrig);

$sha = $arq->sha256();
$tamanho = $arq->tamanho;
$stored = bin2hex(random_bytes(12)) . '.' . $ext;
$chave = Armazenamento::chaveCallApp($so, $stored, $nomeOrig);
$g = Armazenamento::guardarEm($arq, Config::PASTA_APP, $stored, 'application/octet-stream', $chave);

Config::set(Config::S_APP . $so, (string) json_encode([
    'versao'        => $versao,
    'nome'          => 'APP-Operacao-UNIFI-' . $versao . '.' . $ext,
    'tamanho'       => $tamanho,
    'sha256'        => $sha,
    'stored_name'   => $stored,
    'storage'       => (string) $g['onde'],
    'storage_key'   => (string) ($g['chave'] ?? ''),
    'publicado_em'  => date('Y-m-d H:i:s'),
    'publicado_por' => 'Implantação pelo terminal',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));

if ($anterior !== null) {
    try {
        Armazenamento::excluir([
            'stored_name' => $anterior['stored_name'], 'storage' => $anterior['storage'], 'storage_key' => $anterior['storage_key'],
        ], Config::PASTA_APP);
    } catch (Throwable $e) {
        fwrite(STDERR, 'aviso: não apaguei o instalador antigo: ' . $e->getMessage() . "\n");
    }
}

CallAppEvento::registrar('versao_publicada', '127.0.0.1', null, null, 'Implantação pelo terminal',
    Config::SISTEMAS[$so]['rotulo'] . ' ' . $versao . ($anterior !== null ? ' (antes ' . $anterior['versao'] . ')' : ''));

printf("Publicado: %s %s · %s · %d bytes · sha256 %s · %s%s\n", $so, $versao, $nomeOrig, $tamanho, $sha,
    $g['onde'], $g['chave'] ? ' (' . $g['chave'] . ')' : '');
