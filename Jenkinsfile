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
def deployEnv(String envName) {
    def cfg = envConfig(envName)
    def comps = appConfig().components
    withEnv(["NS=${cfg.ns}", "OVERLAY=${cfg.overlay}"]) {
        withCredentials([file(credentialsId: cfg.kubeCred, variable: 'KUBECONFIG')]) {
            sh 'set -e; kubectl apply -k "$OVERLAY" --kubeconfig="$KUBECONFIG"'

            for (c in comps) {
                withEnv(["DEPLOY=${c.deployment}", "CONTAINER=${c.container}", "IMG=${imageRef(c)}"]) {
                    sh 'set -e; kubectl set image "deployment/$DEPLOY" "$CONTAINER=$IMG" -n "$NS" --kubeconfig="$KUBECONFIG"'
                }
            }

            boolean ok = true
            for (c in comps) {
                if (!ok) { break }
                withEnv(["DEPLOY=${c.deployment}"]) {
                    int rc = sh(returnStatus: true,
                                script: 'kubectl rollout status "deployment/$DEPLOY" -n "$NS" --kubeconfig="$KUBECONFIG" --timeout=180s')
                    if (rc != 0) { ok = false }
                }
            }

            if (!ok) {
                echo "Rollout failed in ${cfg.ns}: rolling back every component to its previous revision"
                for (c in comps) {
                    withEnv(["DEPLOY=${c.deployment}"]) {
                        sh 'kubectl rollout undo "deployment/$DEPLOY" -n "$NS" --kubeconfig="$KUBECONFIG" || true'
                    }
                }
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
                            echo "Building commit ${env.GIT_COMMIT_SHORT} as ${env.IMAGE_TAG}"
                        }
                    }
                }

                stage('Build Images') {
                    steps { script { buildImages() } }
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
                    steps { script { smokeTest('staging') } }
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
