# Limitações conhecidas

[English](../limitations.md) | **Português (Brasil)**

- A grade é sempre 3x3, com nomes de direção fixos e a célula central ignorada.
- Só camadas e grupos de nível superior podem ser escolhidos. Um grupo é importado como a combinação
  dos seus filhos; filhos ocultos dentro de um grupo podem ser incluídos, porque as camadas ocultas
  ficam visíveis para a exportação.
- A contagem de repetições da tag definida no Aseprite é ignorada: só o sufixo de loop decide se uma
  animação fica em loop.
- Um arquivo sem tags gera uma animação por direção com a timeline inteira, com o nome da direção
  (`down`). Ela não fica em loop.
- Nomes de camada com `,` ou `:` não aparecem na lista de `layers/layer`.
- O Aseprite é necessário para importar. Os recursos importados ficam em `.godot/`, que normalmente
  não vai para o controle de versão, então todo mundo que abre o projeto precisa do Aseprite.
- Sincronizar um AnimationPlayer não pode ser desfeito com *Undo*.
- Testado só no Windows, com Godot 4.7.1 e Aseprite 1.3.18.
