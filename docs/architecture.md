## Arquitetura do repositório

Este repositório segue uma separação explícita entre:

- infraestrutura da máquina (site)
- definição da aplicação (template)
- descoberta automática do ambiente (bootstrap)

Essa separação é fundamental para garantir **reprodutibilidade, portabilidade e consistência institucional**.

### Relação entre `.env`, `site` e `template`

O fluxo completo é:

```text
.env → bootstrap → site → template → ambiente final
````

### Componentes

#### 1. Bootstrap (`scripts/bootstrap/`)

Responsável por **descobrir automaticamente o ambiente da máquina**.

* `env/<machine>.env`: define o ambiente mínimo da máquina
* `bootstrap_spack_site.sh`: gera automaticamente:

  * `compilers.yaml`
  * `packages.yaml`

> O `.env` deve conter apenas o mínimo necessário para que o Spack entenda a máquina.

Para detalhes completos, consulte:

```text
scripts/bootstrap/env/README.md
```

#### 2. Site (`configs/sites/<machine>/`)

Define a **configuração institucional da máquina**.

Exemplo:

```text
configs/sites/egeon/
```

Contém:

* `compilers.yaml` → compiladores disponíveis 
* `packages.yaml` → externals e providers 
* `modules.yaml` → estrutura de módulos 
* `config.yaml` → configuração geral do Spack 

### Interpretação importante

> O diretório `configs/sites/<machine>/` representa uma **configuração escolhida em um determinado momento**.

Ou seja:

* é uma **fotografia da máquina**
* pode ser atualizada a qualquer momento
* deve ser regenerada quando o ambiente da máquina mudar

### Como atualizar um site

1. Ajustar o `.env` correspondente
2. Executar o bootstrap:

```bash
./bootstrap_spack_site.sh --site <machine>
```

3. Revisar os arquivos gerados
4. Atualizar `configs/sites/<machine>/`

#### 3. Template (`configs/templates/`)

Define o ambiente da aplicação.

Exemplo:

```text
configs/templates/mpas-bundle/spack.yaml
```

Esse arquivo define:

* dependências do MPAS-JEDI
* bibliotecas científicas
* configuração do ambiente

> O template é comum a todas as máquinas.

---

### Regra crítica

> O `site` NÃO deve conter dependências do MPAS-BUNDLE.

Essas dependências já estão no template:

```text
configs/templates/mpas-bundle/spack.yaml
```

---

### Interpretação prática

| Componente  | Função                   |
| ----------- | ------------------------ |
| `.env`      | descobrir a máquina      |
| `site/`     | definir a infraestrutura |
| `template/` | definir a aplicação      |
| Spack       | montar o ambiente final  |

---

### Resultado final

```text
site (máquina)
+
template (mpas-bundle)
=
ambiente completo MPAS-JEDI
```
