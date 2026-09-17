# Desenhando o sprite

[English](../drawing-the-sprite.md) | **Português (Brasil)**

Como organizar o arquivo do Aseprite. As opções do dock Import que o leem estão em
[Importação](importing.md#opções-de-importação).

- Faça o canvas com três células de largura e três de altura, por exemplo **144x192** para
  personagens de 48x64, e desenhe cada direção na sua célula. Ajustar a grade do Aseprite
  (*View > Grid > Grid Settings*) para o tamanho da célula ajuda a manter cada pose dentro da sua
  célula.
- Pixels que atravessam a borda de uma célula acabam na animação da direção vizinha.
- Por padrão, todas as camadas são combinadas nas animações. Comece o nome das camadas auxiliares
  (guias, referências) com `_` para deixá-las de fora, ou escolha uma única camada ou grupo em
  `layers/layer`.
- Use uma tag por animação. As durações dos frames e a direção da tag (forward, reverse, ping-pong,
  ping-pong reverse) são mantidas. Termine uma tag com `_loop` (`idle_loop`) para que suas animações
  fiquem em loop.
- Frames fora de qualquer tag não são importados, a menos que o arquivo não tenha tags.

## Sprites sem direção

Um jogo top-down também tem sprites que não olham para lugar nenhum: a poeira de corrida, a faísca
de impacto, o brilho de um item. Coloque `grid/directions` em `none` no dock Import e o frame vira
uma célula única, desenhada de ponta a ponta, sem grade para respeitar. Tags, durações dos frames, a
direção da tag e o sufixo `_loop` funcionam igual, e as animações recebem só o nome da tag:
`run_loop` gera `run`.
