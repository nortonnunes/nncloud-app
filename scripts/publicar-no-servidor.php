<?php
/*
 * Publica um instalador do NN Conversas pelo terminal — o MESMO caminho da tela
 * Sistema → NN Conversas → Aplicativo (o núcleo App\Core\AppDesktop\Instaladores:
 * extensão, assinatura do formato, SHA-256, Armazenamento, setting), para um
 * arquivo que já está no servidor.
 *
 * Roda NO SERVIDOR, lido pela entrada padrão (o script não precisa estar lá):
 *   scp -i ~/.ssh/macLaercio.pem NN-Conversas-1.0.0.dmg ubuntu@52.67.111.122:/tmp/
 *   ssh -i ~/.ssh/macLaercio.pem ubuntu@52.67.111.122 \
 *     "cd /var/www/noc.nortonnunes.com.br && sudo -u www-data php -- macos 1.0.0 /tmp/NN-Conversas-1.0.0.dmg" \
 *     < scripts/publicar-no-servidor.php
 * <so> = windows | macos | linux. Mesma versão já publicada só é trocada com --forcar.
 */
declare(strict_types=1);

if (PHP_SAPI !== 'cli') { exit(1); }
require getcwd() . '/bootstrap.php';

use App\Core\ArquivoRecebido;
use App\Core\ConversasApp\Config;
use App\Models\ConversasAppEvento;

$args = array_values(array_filter(array_slice($argv, 1), fn($a) => $a !== '--forcar'));
$forcar = in_array('--forcar', $argv, true);
[$so, $versao, $origem] = $args + ['', '', ''];

function falha(string $m): never { fwrite(STDERR, "ERRO: $m\n"); exit(2); }

if (!Config::disponivel()) falha('falta rodar o php migrate (201)');
if (!isset(Config::SISTEMAS[$so])) falha("sistema inválido ($so)");
if (!Config::versaoValida($versao)) falha("versão inválida ($versao)");
if (!is_file($origem) || !is_readable($origem)) falha("arquivo não encontrado: $origem");

$inst = Config::instaladores();
$anterior = $inst->instalador($so);
if ($anterior !== null && $anterior['versao'] === $versao && !$forcar) {
    echo "Já publicado: $so {$versao} (use --forcar para substituir)\n";
    exit(0);
}

// Copia para o temporário do próprio sistema (mesma partição de storage/): o
// Armazenamento grava por rename.
$nomeOrig = basename($origem);
$ext = (string) preg_replace('/[^a-z0-9]+/', '', strtolower(pathinfo($nomeOrig, PATHINFO_EXTENSION)));
$tmp = ArquivoRecebido::dirTmp() . '/pub_' . bin2hex(random_bytes(8)) . '.' . $ext;
if (!copy($origem, $tmp)) falha('não consegui copiar para storage/tmp_uploads');

try {
    $r = $inst->publicar($so, $versao, ArquivoRecebido::deArquivoMontado($tmp, $nomeOrig), 'Implantação pelo terminal');
} catch (\DomainException $e) {
    @unlink($tmp);
    falha($e->getMessage());
}
$atual = $r['atual'];
ConversasAppEvento::registrar('versao_publicada', '127.0.0.1', null, 'Implantação pelo terminal', '',
    Config::SISTEMAS[$so]['rotulo'] . ' ' . $versao . ($r['anterior'] !== null ? ' (antes ' . $r['anterior']['versao'] . ')' : ''));

printf("Publicado: %s %s · %s · %d bytes · sha256 %s · %s%s\n", $so, $versao, $nomeOrig, (int) $atual['tamanho'], $atual['sha256'],
    $atual['storage'], $atual['storage_key'] !== '' ? ' (' . $atual['storage_key'] . ')' : '');
