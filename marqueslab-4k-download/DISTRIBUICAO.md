# Distribuição pública no macOS — o que falta e como configurar

O código, o empacotamento, a assinatura, a notarização, a validação e a
publicação do release já estão implementados e versionados neste repositório.

**O que ainda não existe são as credenciais da Apple.** Elas são pessoais,
pagas e só podem ser criadas por você na sua conta Apple Developer. Sem elas
nenhuma ferramenta do mundo consegue produzir um aplicativo macOS que abra sem
o aviso de "desenvolvedor não identificado".

O pipeline foi construído para **parar exatamente nesse ponto**: o job
`preflight` do workflow de release falha com a lista dos Secrets ausentes e
nenhum build ad-hoc é publicado.

---

## 1. Pré-requisito pago

Conta no **Apple Developer Program** — US$ 99/ano, em <https://developer.apple.com/programs/>.

A conta gratuita **não** emite certificados Developer ID e, portanto, não
permite distribuição fora da Mac App Store.

---

## 2. Criar o certificado Developer ID Application

1. Abra o app **Acesso às Chaves** (Keychain Access) no seu Mac.
2. Menu **Acesso às Chaves → Assistente de Certificado → Solicitar um
   certificado a uma autoridade de certificação**.
3. Preencha o e-mail, marque **Salvo no disco** e gere o arquivo
   `CertificateSigningRequest.certSigningRequest`.
4. Acesse <https://developer.apple.com/account/resources/certificates/list>.
5. Clique em **+**, escolha **Developer ID Application** e envie o `.certSigningRequest`.
6. Baixe o `.cer` gerado e dê duplo clique para instalá-lo no chaveiro.

> Atenção: **Apple Development** e **Mac Developer** não servem. O script de
> assinatura rejeita explicitamente qualquer identidade que não seja
> `Developer ID Application`.

## 3. Exportar o certificado como `.p12`

1. No **Acesso às Chaves**, categoria **Meus certificados**, localize
   `Developer ID Application: SEU NOME (TEAMID)`.
2. Clique com o botão direito → **Exportar** → formato **Troca de Informações
   Pessoais (.p12)**.
3. Defina uma senha forte — ela será o Secret `APPLE_CERTIFICATE_PASSWORD`.
4. Converta o arquivo para base64:

```bash
base64 -i Developer_ID_Application.p12 | pbcopy
```

O conteúdo copiado é o Secret `APPLE_CERTIFICATE_BASE64`.

## 4. Criar a senha específica de app (notarização)

1. Acesse <https://account.apple.com/account/manage>.
2. Em **Segurança → Senhas específicas de app**, clique em **Gerar senha**.
3. Dê o nome `notarytool` e guarde a senha no formato `abcd-efgh-ijkl-mnop`.

## 5. Descobrir o Team ID

Está em <https://developer.apple.com/account> → **Membership details** →
**Team ID** (10 caracteres, por exemplo `A1B2C3D4E5`). Também aparece entre
parênteses no nome do certificado.

---

## 6. Cadastrar os Secrets no GitHub

Repositório → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Conteúdo | Obrigatório |
| --- | --- | --- |
| `APPLE_CERTIFICATE_BASE64` | `.p12` do Developer ID Application em base64 | Sim |
| `APPLE_CERTIFICATE_PASSWORD` | senha usada ao exportar o `.p12` | Sim |
| `APPLE_TEAM_ID` | Team ID de 10 caracteres | Sim |
| `APPLE_ID` | e-mail da conta Apple Developer | Sim¹ |
| `APPLE_APP_PASSWORD` | senha específica de app (`abcd-efgh-ijkl-mnop`) | Sim¹ |
| `APPLE_SIGNING_IDENTITY` | nome exato da identidade, se você tiver mais de uma | Não |

¹ Alternativa mais robusta: em vez de `APPLE_ID` + `APPLE_APP_PASSWORD`, use uma
chave da App Store Connect API cadastrando `APPLE_API_KEY_ID`,
`APPLE_API_ISSUER_ID` e `APPLE_API_KEY_BASE64` (o arquivo `.p8` em base64). O
pipeline detecta automaticamente qual dos dois métodos está configurado e
prefere a API key.

Comando equivalente pelo terminal, se preferir:

```bash
gh secret set APPLE_CERTIFICATE_BASE64 --repo cassiomarquesdj-web/Servidor-Local-Marques-Lab < cert.b64
```

---

## 7. Gerar o release

Com os Secrets configurados, publique uma tag:

```bash
git tag 4kdownload-v1.0.0 && git push origin 4kdownload-v1.0.0
```

Ou execute manualmente o workflow **4K Download — Release macOS assinado e
notarizado** em **Actions**.

O workflow então, sozinho:

1. confere as credenciais (`preflight`);
2. compila o `.app` em `macos-14` (Apple Silicon) e `macos-13` (Intel);
3. tenta também um binário **Universal 2**;
4. assina cada binário Mach-O de dentro para fora com Hardened Runtime e timestamp;
5. envia o aplicativo para a notarização da Apple e anexa o ticket;
6. monta o DMG com o atalho para `/Applications`, assina o DMG;
7. notariza e faz o staple **também do DMG**;
8. valida `codesign --verify`, `spctl --assess`, `xcrun stapler validate`;
9. monta o DMG e executa o aplicativo de dentro dele, fazendo um download e uma
   conversão MP3 reais;
10. publica o GitHub Release com os DMGs e as instruções de instalação.

Se qualquer uma dessas etapas falhar, **nada é publicado**.

---

## 8. Verificação local (opcional)

Depois de exportar as mesmas variáveis no seu Mac:

```bash
cd marqueslab-4k-download && packaging/release_macos.sh
```

Para um build local sem assinatura, apenas para desenvolvimento:

```bash
cd marqueslab-4k-download && MARQUESLAB_ALLOW_HOST_PYTHON=1 packaging/build_app.sh
```

Esse bundle **não** é distribuível: ele é assinado ad-hoc e herda o requisito de
macOS do Python instalado na sua máquina. Serve apenas para testar a aplicação.
