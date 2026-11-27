// Os emojis do chat — os MESMOS grupos e a mesma linha rápida de reações do
// site (`comunicacao.js`: EMOJI_GRUPOS, QUICK_EMOJIS, GRID_EMOJIS).
import 'package:flutter/material.dart';

import '../../tema.dart';

const reacoesRapidas = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

const reacoesGrade = [
  ...reacoesRapidas,
  '😀', '😅', '😊', '😍', '😘', '😎', '🤔', '😴', '🙄', '😳',
  '😭', '😡', '🥳', '🤩', '😇', '🤗', '🤯', '😱', '👏', '🙌',
  '🤝', '💪', '👌', '✌️', '🤞', '🔥', '⭐', '✅', '❌', '💯',
  '🎉', '🎯', '💡', '☕', '🍕', '😆', '😉', '😜',
];

const gruposEmoji = <(String, List<String>)>[
  ('Rostos', ['😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩','😘','😗','😚','😋','😛','🤪','🤨','🧐','🤓','😎','🥳','😏','😒','😞','😔','😟','😕','🙁','😣','😖','😫','😩','🥺','😢','😭','😤','😠','😡','🤬','🤯','😳','🥵','🥶','😱','😨','😰','😥','😓','🤗','🤔','🤭','🤫','😶','😐','😑','😬','🙄','😯','😴','🤤','😪','😵','🤐','🥴','🤢','🤮','🤧','😷','🤒','🤕']),
  ('Gestos', ['👍','👎','👌','🤌','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','👇','☝️','✋','🤚','🖐️','🖖','👋','🤝','🙏','💪','🦾','✍️','👏','🙌','👐','🤲','🫶']),
  ('Símbolos', ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','💔','❣️','💕','💞','💯','✅','❌','⚠️','❗','❓','💡','🔥','⭐','🌟','✨','🎉','🎊','🏆','🥇','📌','📎','🔒','🔔','⏰','📅','📈','📉','💰','💸','🧾','📝','📊']),
  ('Objetos', ['☕','🍕','🍔','🍟','🎂','🍰','🍻','🥂','🚗','✈️','🏠','🏢','💻','🖥️','📱','⌨️','🖱️','🖨️','📞','📧','📦','🗂️','🗓️','🧠','🎯','🚀','⚙️','🔧','🧰']),
];

/// O painel de emojis do compositor (fica aberto: dá para escolher vários).
Future<void> abrirEmojis(BuildContext context, void Function(String) escolher) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black12,
    builder: (d) {
      final p = d.pal;
      return Align(
        alignment: const Alignment(-.55, .78),
        child: Material(
          color: p.card,
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 360),
            child: ListView(padding: const EdgeInsets.all(12), shrinkWrap: true, children: [
              for (final g in gruposEmoji) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                  child: Text(g.$1, style: TextStyle(fontWeight: FontWeight.w700, color: p.muted, fontSize: 12.5)),
                ),
                Wrap(children: [
                  for (final e in g.$2)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => escolher(e),
                      child: Padding(padding: const EdgeInsets.all(5), child: Text(e, style: const TextStyle(fontSize: 22))),
                    ),
                ]),
              ],
            ]),
          ),
        ),
      );
    },
  );
}

/// A grade de reações (o "+" ao lado da linha rápida). Devolve o emoji escolhido.
Future<String?> escolherReacao(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Reagir'),
      content: SizedBox(
        width: 360,
        child: Wrap(spacing: 2, runSpacing: 2, children: [
          for (final e in reacoesGrade)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.pop(d, e),
              child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 24))),
            ),
        ]),
      ),
    ),
  );
}
