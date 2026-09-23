# Desenhando o sprite

[English](../drawing-the-sprite.md) | **Português (Brasil)**

Como organizar o arquivo do Aseprite. As opções do dock Import que o leem estão em
[Importação](importing.md#opções-de-importação).

- Faça o canvas do tamanho de um frame do sprite. O canvas inteiro é importado, de ponta a ponta.
- Por padrão, todas as camadas são combinadas nas animações. Comece o nome das camadas auxiliares
  (guias, referências) com `_` para deixá-las de fora, ou escolha uma única camada ou grupo em
  `layers/layer`.
- Use uma tag por animação. As durações dos frames e a direção da tag (forward, reverse, ping-pong,
  ping-pong reverse) são mantidas. Termine uma tag com `_loop` (`idle_loop`) para que sua animação
  fique em loop; a animação recebe o nome da tag sem ele (`idle`).
- Frames fora de qualquer tag não são importados, a menos que o arquivo não tenha tags.
- Um personagem que só vira para a esquerda e para a direita precisa de um lado só: desenhe-o
  olhando para a direita e espelhe-o no jogo com `flip_h`.

## Uma grade 3x3 de direções

Um personagem que olha para cima, para baixo e para os lados pode ter todas as direções num arquivo
só: faça o canvas com três células de largura e três de altura, por exemplo **144x192** para
personagens de 48x64, desenhe cada direção na sua célula e coloque `grid/directions` em `3x3`. Cada
tag passa a gerar uma animação por direção. [Personagens top-down](top-down.md) descreve o layout e
como ativar a grade para o projeto inteiro.
