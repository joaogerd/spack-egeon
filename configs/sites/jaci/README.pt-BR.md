# Configuração da Plataforma JACI

For the English version of this document, see [README.md](README.md).

Este diretório contém os arquivos de configuração específicos da plataforma **JACI**, necessários para a integração do supercomputador ao ecossistema **spack-stack**.

Os arquivos aqui mantidos descrevem a toolchain de compiladores disponível na máquina, os pacotes externos fornecidos pelo sistema, o comportamento geral do Spack e a política de geração de módulos adotada para esta plataforma. Em conjunto, eles estabelecem a base de configuração necessária para a criação de ambientes de software consistentes, reprodutíveis e sustentáveis no JACI.

## Finalidade

A finalidade deste diretório é centralizar todos os elementos de configuração que descrevem o ambiente de software do **JACI** sob a perspectiva da integração com o **spack-stack**.

Isso inclui:

- definição do conjunto de compiladores disponíveis no sistema;
- registro de pacotes e bibliotecas externas fornecidas pelo ambiente da máquina;
- configuração do comportamento global do Spack para esta plataforma;
- definição da organização e exposição dos módulos de ambiente para os usuários.

Ao manter esses arquivos organizados em um diretório específico da máquina, a plataforma JACI pode ser integrada de forma estruturada e transparente, facilitando a criação de ambientes, a manutenção, a validação e futuras atualizações.

## Arquivos esperados

Espera-se que os seguintes arquivos sejam mantidos neste diretório:

- **`compilers.yaml`**  
  Declara os compiladores disponíveis no JACI, incluindo caminhos dos executáveis, versões, arquitetura de destino e demais atributos necessários para o uso correto pelo Spack.

- **`config.yaml`**  
  Define parâmetros globais de configuração do Spack para esta plataforma, como organização das instalações, comportamento de build, uso de cache e demais preferências de escopo institucional.

- **`modules.yaml`**  
  Especifica como os módulos de ambiente serão gerados e organizados para os softwares instalados via Spack, incluindo convenções de nomenclatura, hierarquia e política de disponibilização aos usuários.

- **`packages.yaml`**  
  Descreve os pacotes externos já instalados e disponíveis no JACI, como bibliotecas MPI, NetCDF, HDF5 e outras dependências fornecidas pelo sistema que devem ser reutilizadas em vez de recompiladas pelo Spack.

## Escopo

O conteúdo deste diretório deve se restringir às configurações específicas da plataforma **JACI**.

Este diretório não deve conter:

- definições de ambientes específicas de aplicações;
- configurações genéricas de templates compartilhados entre múltiplas máquinas;
- arquivos temporários, artefatos de teste ou ajustes locais de usuários que não façam parte da definição institucional da plataforma.

## Diretrizes de manutenção

Todos os arquivos deste diretório devem refletir o estado real do ambiente operacional do JACI. Qualquer alteração em compiladores, bibliotecas externas, organização de módulos ou políticas da plataforma deve ser avaliada e, quando pertinente, incorporada a estes arquivos de configuração.

As atualizações devem ser realizadas com atenção a:

- consistência técnica com o ambiente efetivamente implantado;
- reprodutibilidade dos builds de software;
- compatibilidade com a versão do **spack-stack** adotada;
- clareza e manutenibilidade da definição da plataforma ao longo do tempo.

## Observação final

Este diretório representa a camada oficial de **configuração de site** da plataforma JACI dentro do repositório. Sua qualidade e precisão são essenciais para garantir que os ambientes gerados com o **spack-stack** permaneçam estáveis, reprodutíveis e aderentes às características do supercomputador de destino.
