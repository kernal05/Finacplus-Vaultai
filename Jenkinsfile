// =============================================================================
// VaultAI CI/CD pipeline (Declarative Pipeline + Groovy helper functions)
//
// Flow:  build -> load images -> [secret -> deploy -> smoke test] STAGING
//        -> manual approval (no executor held) -> same image to PRODUCTION
//
// Environment differences live in k8s/overlays/<env> (Kustomize) and in
// envConfig() below. Adding an environment = one overlay folder + one map entry.
// Images are built once and promoted, never rebuilt for production.
// =============================================================================

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

// ---- Reusable steps ----------------------------------------------------------

// Create/update the app secret BEFORE deploying so pods start with current values.
def syncSecret(String envName) {
    def cfg = envConfig(envName)
    withEnv(["NS=${cfg.ns}"]) {
        withCredentials([
            file(credentialsId: cfg.kubeCred, variable: 'KUBECONFIG'),
            string(credentialsId: cfg.keyCred, variable: 'ANTHROPIC_KEY')
        ]) {
            sh '''
                set +x
                set -e
                kubectl create secret generic vaultai-secrets \
                    --from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_KEY" \
                    -n "$NS" --kubeconfig="$KUBECONFIG" \
                    --dry-run=client -o yaml | kubectl apply -f - --kubeconfig="$KUBECONFIG"
            '''
        }
    }
}

// Apply overlay, roll to this build's images, roll back automatically on failure.
def deployEnv(String envName) {
    def cfg = envConfig(envName)
    withEnv(["NS=${cfg.ns}", "OVERLAY=${cfg.overlay}"]) {
        withCredentials([file(credentialsId: cfg.kubeCred, variable: 'KUBECONFIG')]) {
            sh '''
                set -e
                kubectl apply -k "$OVERLAY" --kubeconfig="$KUBECONFIG"
                kubectl set image deployment/vaultai-api vaultai-api="$API_IMAGE" -n "$NS" --kubeconfig="$KUBECONFIG"
                kubectl set image deployment/vaultai-web vaultai-web="$WEB_IMAGE" -n "$NS" --kubeconfig="$KUBECONFIG"
                if ! kubectl rollout status deployment/vaultai-api -n "$NS" --kubeconfig="$KUBECONFIG" --timeout=180s \
                   || ! kubectl rollout status deployment/vaultai-web -n "$NS" --kubeconfig="$KUBECONFIG" --timeout=180s; then
                    echo "Rollout failed in $NS - rolling back to previous revision"
                    kubectl rollout undo deployment/vaultai-api -n "$NS" --kubeconfig="$KUBECONFIG" || true
                    kubectl rollout undo deployment/vaultai-web -n "$NS" --kubeconfig="$KUBECONFIG" || true
                    exit 1
                fi
            '''
        }
    }
}

def smokeTest(String envName) {
    def cfg = envConfig(envName)
    withEnv(["NS=${cfg.ns}"]) {
        withCredentials([file(credentialsId: cfg.kubeCred, variable: 'KUBECONFIG')]) {
            sh '''
                set -e
                kubectl get pods -n "$NS" --kubeconfig="$KUBECONFIG"
                kubectl exec -n "$NS" --kubeconfig="$KUBECONFIG" deploy/vaultai-api -- \
                    python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/healthz').read().decode())"
                kubectl exec -n "$NS" --kubeconfig="$KUBECONFIG" deploy/vaultai-web -- \
                    wget -qO- http://127.0.0.1/healthz
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
        PROD_APPROVERS = ''
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
                            env.API_IMAGE = "vaultai-api:${env.IMAGE_TAG}"
                            env.WEB_IMAGE = "vaultai-web:${env.IMAGE_TAG}"
                            echo "Building commit ${env.GIT_COMMIT_SHORT} as ${env.IMAGE_TAG}"
                        }
                    }
                }

                stage('Build API Image') {
                    steps {
                        echo "Building ${env.API_IMAGE} from api/Dockerfile"
                        sh '''
                            set -e
                            docker build -t "$API_IMAGE" -f api/Dockerfile api/
                        '''
                    }
                }

                stage('Build Web Image') {
                    steps {
                        echo "Building ${env.WEB_IMAGE} from app/Dockerfile"
                        sh '''
                            set -e
                            docker build -t "$WEB_IMAGE" -f app/Dockerfile .
                        '''
                    }
                }

                stage('Load Images into Minikube') {
                    when { branch 'main' }
                    steps {
                        sh '''
                            set -e
                            docker save "$API_IMAGE" | docker exec -i minikube docker load
                            docker exec minikube docker image inspect "$API_IMAGE" > /dev/null
                            docker save "$WEB_IMAGE" | docker exec -i minikube docker load
                            docker exec minikube docker image inspect "$WEB_IMAGE" > /dev/null
                        '''
                    }
                }

                stage('Sync Staging Secret') {
                    when { branch 'main' }
                    steps { script { syncSecret('staging') } }
                }

                stage('Deploy Staging') {
                    when { branch 'main' }
                    steps { script { deployEnv('staging') } }
                }

                stage('Staging Smoke Test') {
                    when { branch 'main' }
                    steps { script { smokeTest('staging') } }
                }
            }
            post {
                always { cleanWs() }
            }
        }

        // Runs on NO executor while waiting for a human.
        stage('Approve Production') {
            when { branch 'main'; beforeAgent true }
            steps {
                script {
                    def decision = timeout(time: 30, unit: 'MINUTES') {
                        input(
                            message: "Staging passed for ${env.GIT_COMMIT_SHORT}. Promote ${env.API_IMAGE} / ${env.WEB_IMAGE}?",
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
                    branch 'main'
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
                    steps { script { smokeTest('prod') } }
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
                    echo "Deployed ${env.API_IMAGE} and ${env.WEB_IMAGE} to staging and production."
                } else {
                    echo "Deployed ${env.API_IMAGE} and ${env.WEB_IMAGE} to staging. Production skipped."
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
