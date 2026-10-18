// =============================================================================
// CI/CD pipeline (Declarative Pipeline + Groovy helper functions)
//
// Flow:  build -> load images -> [secret -> deploy -> smoke test] STAGING
//        -> manual approval (no executor held) -> same image to PRODUCTION
//
// TO ONBOARD ANOTHER SERVICE:   edit appConfig()  (one map per component)
// TO ADD AN ENV OR CLUSTER:     add an entry in envConfig() + k8s/overlays/<env>
// Images are built once and promoted, never rebuilt for production.
// =============================================================================

// ---- Application configuration (edit this to onboard a service) --------------
def appConfig() {
    return [
        deployBranch: 'main',        // only this branch deploys
        minikubeNode: 'minikube',    // local-dev image loading; use a registry push for real clusters
        secretName  : 'vaultai-secrets',
        secretKey   : 'ANTHROPIC_API_KEY',
        components  : [
            [deployment: 'vaultai-api', container: 'vaultai-api', image: 'vaultai-api',
             dockerfile: 'api/Dockerfile', context: 'api/',
             smoke: 'python -c "import urllib.request; print(urllib.request.urlopen(\'http://localhost:8000/healthz\').read().decode())"'],
            [deployment: 'vaultai-web', container: 'vaultai-web', image: 'vaultai-web',
             dockerfile: 'app/Dockerfile', context: '.',
             smoke: 'wget -qO- http://127.0.0.1/healthz'],
        ],
    ]
}

// ---- Per-environment configuration -------------------------------------------
// Give prod its own kubeconfig / API key credentials by changing the two
// credential IDs in the prod entry (least privilege: prod creds -> prod only).
def envConfig(String name) {
    def all = [
        staging: [ns: 'vaultai-staging', overlay: 'k8s/overlays/staging',
                  kubeCred: 'minikube-kubeconfig', keyCred: 'vaultai-anthropic-key'],
        prod   : [ns: 'vaultai-prod',    overlay: 'k8s/overlays/prod',
                  kubeCred: 'minikube-kubeconfig', keyCred: 'vaultai-anthropic-key'],
    ]
    if (!all.containsKey(name)) {
        error "Unknown environment '${name}'"
    }
    return all[name]
}

// ---- Helpers -----------------------------------------------------------------

def imageRef(Map c) {
    return "${c.image}:${env.IMAGE_TAG}".toString()
}

def imageList() {
    def refs = []
    for (c in appConfig().components) {
        refs << imageRef(c)
    }
    return refs.join(' / ')
}

def buildImages() {
    for (c in appConfig().components) {
        withEnv(["IMG=${imageRef(c)}", "DOCKERFILE=${c.dockerfile}", "CONTEXT=${c.context}"]) {
            echo "Building ${env.IMG} from ${env.DOCKERFILE}"
            sh 'set -e; docker build -t "$IMG" -f "$DOCKERFILE" "$CONTEXT"'
        }
    }
}

def loadImages() {
    def app = appConfig()
    for (c in app.components) {
        withEnv(["IMG=${imageRef(c)}", "NODE=${app.minikubeNode}"]) {
            sh '''
                set -e
                docker save "$IMG" | docker exec -i "$NODE" docker load
                docker exec "$NODE" docker image inspect "$IMG" > /dev/null
            '''
        }
    }
}

// Create/update the app secret BEFORE deploying so pods start with current values.
def syncSecret(String envName) {
    def cfg = envConfig(envName)
    def app = appConfig()
    withEnv(["NS=${cfg.ns}", "SECRET=${app.secretName}", "SKEY=${app.secretKey}"]) {
        withCredentials([
            file(credentialsId: cfg.kubeCred, variable: 'KUBECONFIG'),
            string(credentialsId: cfg.keyCred, variable: 'ANTHROPIC_KEY')
        ]) {
            sh '''
                set +x
                set -e
                kubectl create secret generic "$SECRET" \
                    --from-literal="$SKEY=$ANTHROPIC_KEY" \
                    -n "$NS" --kubeconfig="$KUBECONFIG" \
                    --dry-run=client -o yaml | kubectl apply -f - --kubeconfig="$KUBECONFIG"
            '''
        }
    }
}

// Apply overlay, roll to this build's images, roll back automatically on failure.
def rollbackEnv(String envName) {
    def cfg = envConfig(envName)
    def comps = appConfig().components
    withEnv(["NS=${cfg.ns}"]) {
        withCredentials([file(credentialsId: cfg.kubeCred, variable: 'KUBECONFIG')]) {
            echo "Rolling back every component in ${cfg.ns} to its previous revision"
            for (c in comps) {
                withEnv(["DEPLOY=${c.deployment}"]) {
                    sh 'kubectl rollout undo "deployment/$DEPLOY" -n "$NS" --kubeconfig="$KUBECONFIG" || true'
                }
            }
        }
    }
}

def deployEnv(String envName) {
    def cfg = envConfig(envName)
    def comps = appConfig().components

    // Pin this build's tags in the workspace copy of the overlay (never committed),
    // so ONE apply deploys the right image and rollback goes to the previous real build.
    String pins = "\nimages:\n"
    for (c in comps) {
        pins += "  - name: ${c.image}\n    newTag: ${env.IMAGE_TAG}\n"
    }
    writeFile file: 'image-pins.yaml', text: pins

    withEnv(["NS=${cfg.ns}", "OVERLAY=${cfg.overlay}"]) {
        withCredentials([file(credentialsId: cfg.kubeCred, variable: 'KUBECONFIG')]) {
            sh '''
                set -e
                kubectl get nodes --request-timeout=20s --kubeconfig="$KUBECONFIG"
                cat image-pins.yaml >> "$OVERLAY/kustomization.yaml"
                kubectl apply -k "$OVERLAY" --kubeconfig="$KUBECONFIG"
            '''

            boolean ok = true
            for (c in comps) {
                if (!ok) { break }
                withEnv(["DEPLOY=${c.deployment}"]) {
                    int rc = sh(returnStatus: true,
                                script: 'timeout 240 kubectl rollout status "deployment/$DEPLOY" -n "$NS" --kubeconfig="$KUBECONFIG" --timeout=180s')
                    if (rc != 0) { ok = false }
                }
            }

            if (!ok) {
                rollbackEnv(envName)
                error "Rollout failed in ${cfg.ns}; rolled back automatically."
            }
        }
    }
}

def smokeTest(String envName) {
    def cfg = envConfig(envName)
    withEnv(["NS=${cfg.ns}"]) {
        withCredentials([file(credentialsId: cfg.kubeCred, variable: 'KUBECONFIG')]) {
            sh 'kubectl get pods -n "$NS" --kubeconfig="$KUBECONFIG"'
            for (c in appConfig().components) {
                withEnv(["DEPLOY=${c.deployment}", "SMOKE_CMD=${c.smoke}"]) {
                    sh 'set -e; kubectl exec -n "$NS" --kubeconfig="$KUBECONFIG" "deploy/$DEPLOY" -- sh -c "$SMOKE_CMD"'
                }
            }
        }
    }
}

// ---- Quality gates -----------------------------------------------------------
// ruff, trivy and its vulnerability database are installed into the Jenkins container by
// jenkins/install-ci-tools.sh. The stages fail with a clear message if they are missing.

def lintAndValidate() {
    sh '''
        set -e
        command -v ruff > /dev/null || { echo "ruff is not installed in the Jenkins container: run jenkins/install-ci-tools.sh"; exit 1; }
        ruff check api/
        kubectl kustomize k8s/overlays/staging > /dev/null
        kubectl kustomize k8s/overlays/prod > /dev/null
        echo "Lint and manifest validation passed"
    '''
}

// Report only by default: HIGH and CRITICAL findings that HAVE a fix are listed in the build log.
// Set SCAN_ENFORCE_CRITICAL = 'true' in the environment block to fail the build on fixable CRITICAL findings.
def scanImages() {
    boolean enforce = (env.SCAN_ENFORCE_CRITICAL == 'true')
    for (c in appConfig().components) {
        withEnv(["IMG=${imageRef(c)}", "ENFORCE=${enforce}"]) {
            sh '''
                set -e
                command -v trivy > /dev/null || { echo "trivy is not installed in the Jenkins container: run jenkins/install-ci-tools.sh"; exit 1; }
                [ -d "$HOME/.cache/trivy/db" ] || { echo "Trivy database missing in $HOME/.cache/trivy: run jenkins/install-ci-tools.sh"; exit 1; }
                COMMON="--skip-db-update --skip-java-db-update --skip-version-check --no-progress --scanners vuln --ignore-unfixed"
                echo "Scanning $IMG (findings with an available fix, report only)"
                trivy image $COMMON --severity HIGH,CRITICAL --exit-code 0 "$IMG"
                if [ "$ENFORCE" = "true" ]; then
                    echo "Enforcing: failing the build on fixable CRITICAL findings"
                    trivy image $COMMON --severity CRITICAL --exit-code 1 --quiet "$IMG"
                fi
            '''
        }
    }
}

// ---- Pipeline ----------------------------------------------------------------

pipeline {
    agent none   // executors are allocated per stage group, never during approval

    options {
        timestamps()
        disableConcurrentBuilds abortPrevious: true   // a new push replaces a build waiting at approval
        skipDefaultCheckout(true)
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 60, unit: 'MINUTES')
    }

    environment {
        // Comma-separated Jenkins user IDs/groups allowed to approve prod.
        // Empty = any user who can build. Set this before real use.
        PROD_APPROVERS = 'devops-admin'
        // 'true' = fail the build on fixable CRITICAL image findings (report-only while 'false').
        SCAN_ENFORCE_CRITICAL = 'false'
    }

    stages {

        stage('Build and Stage') {
            agent any
            stages {

                stage('Checkout') {
                    steps {
                        checkout scm
                        script {
                            env.GIT_COMMIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                            env.IMAGE_TAG = "build-${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                            echo "Building commit ${env.GIT_COMMIT_SHORT} as ${env.IMAGE_TAG}"
                        }
                    }
                }

                stage('Quality Checks') {
                    steps {
                        timeout(time: 5, unit: 'MINUTES') {
                            script { lintAndValidate() }
                        }
                    }
                }

                stage('Build Images') {
                    steps { script { buildImages() } }
                }

                stage('Image Scan') {
                    steps {
                        timeout(time: 10, unit: 'MINUTES') {
                            script { scanImages() }
                        }
                    }
                }

                stage('Load Images into Minikube') {
                    when { expression { env.BRANCH_NAME == appConfig().deployBranch } }
                    steps { script { loadImages() } }
                }

                stage('Sync Staging Secret') {
                    when { expression { env.BRANCH_NAME == appConfig().deployBranch } }
                    steps { script { syncSecret('staging') } }
                }

                stage('Deploy Staging') {
                    when { expression { env.BRANCH_NAME == appConfig().deployBranch } }
                    steps { script { deployEnv('staging') } }
                }

                stage('Staging Smoke Test') {
                    when { expression { env.BRANCH_NAME == appConfig().deployBranch } }
                    steps {
                        script {
                            try {
                                smokeTest('staging')
                            } catch (e) {
                                echo "Staging smoke test failed: ${e.getMessage()}"
                                rollbackEnv('staging')
                                error "Staging smoke test failed; rolled back automatically. Production was not touched."
                            }
                        }
                    }
                }
            }
            post {
                always { cleanWs() }
            }
        }

        // Runs on NO executor while waiting for a human.
        stage('Approve Production') {
            when { expression { env.BRANCH_NAME == appConfig().deployBranch }; beforeAgent true }
            steps {
                script {
                    def decision = timeout(time: 30, unit: 'MINUTES') {
                        input(
                            message: "Staging passed for ${env.GIT_COMMIT_SHORT}. Promote ${imageList()}?",
                            ok: 'Submit',
                            submitter: env.PROD_APPROVERS ?: '',
                            parameters: [choice(name: 'DECISION',
                                                choices: ['Skip production (staging only)', 'Deploy to production'],
                                                description: 'Default is safe: production is only touched if you pick Deploy.')]
                        )
                    }
                    env.DEPLOY_PROD = (decision == 'Deploy to production') ? 'true' : 'false'
                    echo "Production decision: ${decision}"
                }
            }
        }

        stage('Production') {
            when {
                allOf {
                    expression { env.BRANCH_NAME == appConfig().deployBranch }
                    expression { env.DEPLOY_PROD == 'true' }
                }
                beforeAgent true
            }
            agent any
            stages {
                stage('Checkout (same commit)') {
                    steps { checkout scm }   // multibranch pins this to the build's commit
                }
                stage('Sync Production Secret') {
                    steps { script { syncSecret('prod') } }
                }
                stage('Deploy Production') {
                    steps { script { deployEnv('prod') } }
                }
                stage('Production Smoke Test') {
                    steps {
                        script {
                            try {
                                smokeTest('prod')
                            } catch (e) {
                                echo "Production smoke test failed: ${e.getMessage()}"
                                rollbackEnv('prod')
                                error "Production smoke test failed; rolled back automatically."
                            }
                        }
                    }
                }
            }
            post {
                always { cleanWs() }
            }
        }
    }

    post {
        success {
            script {
                if (env.DEPLOY_PROD == 'true') {
                    echo "Deployed ${imageList()} to staging and production."
                } else {
                    echo "Deployed ${imageList()} to staging. Production skipped."
                }
            }
        }
        failure {
            echo "Pipeline failed at commit ${env.GIT_COMMIT_SHORT}. A failed rollout was rolled back automatically in the failing environment."
            echo 'If staging failed, production was never touched.'
        }
        aborted {
            echo 'Build aborted: approval timed out, was cancelled, or a newer push superseded it. Production was not touched.'
        }
    }
}
