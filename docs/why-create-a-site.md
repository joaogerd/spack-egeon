# Por que criar um site no spack-stack

Quando pensamos em instalar o **MPAS-JEDI** no INPE, é importante separar duas coisas:

* o **spack-stack** cuida do **ambiente de software**;
* o **mpas-bundle** cuida do **código da aplicação**.

Em outras palavras, o `mpas-bundle` organiza e compila os componentes do MPAS-JEDI, enquanto o `spack-stack` prepara toda a base necessária para isso funcionar de forma correta: compiladores, bibliotecas, MPI, Python, módulos e demais dependências.

## O problema real não é só compilar

Compilar uma vez não é o suficiente. O desafio verdadeiro é conseguir repetir o mesmo ambiente depois, em outra máquina, por outra pessoa, ou até na mesma máquina daqui a alguns meses, sem precisar redescobrir tudo de novo.

Esse é o principal motivo para usar o **spack-stack**: ele ajuda a montar um ambiente **reproduzível**, isto é, um ambiente que pode ser reconstruído com muito mais consistência.

Sem isso, cada instalação pode acabar ficando diferente. Um usuário pode usar um compilador, outro pode carregar módulos diferentes, outro pode ter bibliotecas do sistema interferindo no processo. O resultado é um ambiente instável, difícil de manter e difícil de depurar.

## O que significa “criar o site” no spack-stack

No spack-stack, um **site** é o conjunto de arquivos que descreve como uma determinada máquina ou sistema funciona.

Esses arquivos dizem, por exemplo:

* quais compiladores existem naquela máquina;
* quais bibliotecas já instaladas no sistema devem ser reaproveitadas como dependências externas;
* qual implementação de MPI será adotada;
* como os módulos serão gerados;
* quais ajustes locais são necessários para aquela infraestrutura.

Ou seja, criar o site não significa “mexer no Spack inteiro”. Significa **ensinar ao spack-stack como é a máquina onde ele vai trabalhar**.

Esse ponto é fundamental.

## O que é o `linux.default`

No spack-stack, o `linux.default` é uma configuração mínima de partida para sistemas Linux genéricos.

Ele existe para permitir a criação inicial de um ambiente mesmo em máquinas que ainda não possuem um site configurado. Em outras palavras, ele funciona como um modelo básico, útil para começar o processo de configuração.

No entanto, ele não representa fielmente uma máquina real de produção. Ele não conhece, por exemplo, os compiladores realmente adotados pela instituição, as bibliotecas externas disponíveis no sistema, a política de módulos da máquina ou as escolhas locais de MPI.

Por isso, o `linux.default` deve ser entendido como **um ponto de partida técnico**, e não como a configuração final do ambiente.

## Por que não basta usar `linux.default`

O `linux.default` serve para iniciar a configuração, mas não representa corretamente uma máquina real de produção.

Isso acontece porque cada ambiente HPC tem suas próprias características:

* versões diferentes de compiladores;
* diferentes caminhos de instalação;
* políticas diferentes para módulos;
* bibliotecas já instaladas pelo sistema;
* particularidades de cada cluster ou servidor.

Por isso, usar apenas `linux.default` como solução final seria tratar todas as máquinas Linux como se fossem iguais. E elas não são.

No caso do INPE, por exemplo, **EGEON** e **JACI** não devem ser tratados como ambientes genéricos. Cada uma dessas máquinas precisa ter sua configuração local bem definida.

## Por que criar um site é a estratégia correta no INPE

No INPE, o maior problema inicial não é o `mpas-bundle` nem as receitas dos pacotes do Spack. O maior problema é descrever corretamente o ambiente computacional onde tudo será instalado.

Se essa descrição não for feita, o processo de build fica dependente de tentativas manuais, ajustes temporários e escolhas implícitas do sistema. Isso normalmente gera:

* builds diferentes entre máquinas;
* duplicação de dependências;
* conflitos de compilador e MPI;
* dificuldade para reproduzir resultados;
* dificuldade para dar suporte institucional.

Criar um site resolve exatamente isso, porque transforma a configuração da máquina em algo **explícito, organizado e reutilizável**.

Em vez de cada pessoa “dar um jeito” para compilar, o instituto passa a ter uma configuração padronizada.

## Em termos simples: o site é o retrato técnico da máquina

Uma forma simples de entender é esta:

* o **spack-stack** é a ferramenta de montagem;
* o **site** é a descrição da máquina;
* o **mpas-bundle** é o projeto que será compilado em cima desse ambiente.

Sem o site, o spack-stack não conhece a realidade local da infraestrutura. Ele até pode funcionar parcialmente, mas vai trabalhar de forma genérica, e isso quase sempre leva a ajustes improvisados depois.

Com o site, o ambiente passa a refletir a realidade institucional.

## O que fica dentro do site

O site normalmente é formado por arquivos YAML, como:

* `packages.yaml`
* `compilers.yaml`
* `modules.yaml`
* `config.yaml`
* `mirrors.yaml`, em alguns casos

Cada um deles tem uma função específica:

* **`packages.yaml`** define pacotes externos, versões preferidas e provedores;
* **`compilers.yaml`** registra os compiladores que realmente existem na máquina;
* **`modules.yaml`** controla como os módulos serão gerados;
* **`config.yaml`** define opções gerais de comportamento do Spack;
* **`mirrors.yaml`** pode ser usado para espelhos locais de downloads.

Esses arquivos são o coração do site. São eles que transformam uma configuração genérica em uma configuração institucional.

## Qual é o ganho prático disso

Criar o site traz ganhos muito concretos para o INPE:

### 1. Reprodutibilidade

A mesma configuração pode ser reaproveitada depois, sem precisar redescobrir tudo manualmente.

### 2. Padronização

Todos passam a usar a mesma base de compilador, MPI e bibliotecas.

### 3. Manutenção mais simples

Quando surgir um problema, fica mais fácil identificar se ele está na máquina, no ambiente ou no código.

### 4. Escalabilidade institucional

A configuração deixa de ser pessoal e passa a ser institucional. Isso é essencial quando mais de uma pessoa precisa usar ou manter o ambiente.

### 5. Facilidade para evoluir

Depois que o site está bem montado, fica muito mais simples criar novas versões do stack, testar novas releases do `mpas-bundle` ou adaptar a configuração para outra máquina.

## Qual deve ser a lógica no INPE

A abordagem correta no INPE é:

1. escolher a linha do `mpas-bundle` que será usada;
2. escolher a versão compatível do `spack-stack`;
3. criar um ambiente inicial com base em `linux.default`;
4. transformar essa base em um **site institucional real**, como por exemplo:

   * `inpe-egeon`
   * `inpe-jaci`

5. ajustar compiladores, dependências externas, MPI e módulos;
6. só depois resolver completamente as dependências do ambiente, instalar os pacotes e compilar o `mpas-bundle`.

Ou seja: **primeiro se organiza o terreno, depois se constrói a aplicação**.

## Conclusão

Criar o site no spack-stack é necessário porque o problema não é apenas instalar pacotes. O problema é representar corretamente a máquina onde o ambiente será montado.

Sem um site, o spack-stack funciona de forma genérica demais. Com um site, ele passa a refletir a infraestrutura real do INPE.

Por isso, no contexto institucional, criar o site não é um detalhe opcional. É a etapa que transforma uma instalação experimental em uma base de trabalho confiável, reproduzível e sustentável.
