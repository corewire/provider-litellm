/*
Copyright 2024 Corewire.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package clients

import (
	"context"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	litellmProvider "github.com/BerriAI/terraform-provider-litellm/litellm"
	xpv1 "github.com/crossplane/crossplane-runtime/v2/apis/common/v1"

	litellmv1alpha1 "github.com/corewire/provider-litellm/apis/litellm/v1alpha1"
	"github.com/corewire/provider-litellm/apis/v1beta1"
)

func testScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	s := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{
		corev1.AddToScheme,
		v1beta1.SchemeBuilder.AddToScheme,
		litellmv1alpha1.SchemeBuilder.AddToScheme,
	} {
		if err := add(s); err != nil {
			t.Fatalf("cannot build scheme: %v", err)
		}
	}
	return s
}

func providerConfig(key string) *v1beta1.ProviderConfig {
	return &v1beta1.ProviderConfig{
		ObjectMeta: metav1.ObjectMeta{Name: "default"},
		Spec: v1beta1.ProviderConfigSpec{
			Credentials: v1beta1.ProviderCredentials{
				Source: xpv1.CredentialsSourceSecret,
				CommonCredentialSelectors: xpv1.CommonCredentialSelectors{
					SecretRef: &xpv1.SecretKeySelector{
						SecretReference: xpv1.SecretReference{Namespace: "crossplane-system", Name: "creds"},
						Key:             key,
					},
				},
			},
		},
	}
}

func secret(data map[string][]byte) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Namespace: "crossplane-system", Name: "creds"},
		Data:       data,
	}
}

func model(pcName string) *litellmv1alpha1.Model {
	mg := &litellmv1alpha1.Model{ObjectMeta: metav1.ObjectMeta{Name: "model"}}
	if pcName != "" {
		mg.Spec.ProviderConfigReference = &xpv1.Reference{Name: pcName}
	}
	return mg
}

func TestTerraformSetupBuilder(t *testing.T) {
	cases := map[string]struct {
		objects []client.Object
		mg      *litellmv1alpha1.Model
		wantErr string
		want    map[string]any
	}{
		"NoProviderConfigRef": {
			mg:      model(""),
			wantErr: errNoProviderConfig,
		},
		"MissingProviderConfig": {
			mg:      model("default"),
			wantErr: errGetProviderConfig,
		},
		"MissingAPIBase": {
			objects: []client.Object{
				providerConfig("credentials"),
				secret(map[string][]byte{"credentials": []byte(`{"api_key":"k"}`)}),
			},
			mg:      model("default"),
			wantErr: errMissingAPIBase,
		},
		"MissingAPIKey": {
			objects: []client.Object{
				providerConfig("credentials"),
				secret(map[string][]byte{"credentials": []byte(`{"api_base":"http://litellm:4000"}`)}),
			},
			mg:      model("default"),
			wantErr: errMissingAPIKey,
		},
		"InvalidAPIBase": {
			objects: []client.Object{
				providerConfig("credentials"),
				secret(map[string][]byte{"credentials": []byte(`{"api_base":123,"api_key":"k"}`)}),
			},
			mg:      model("default"),
			wantErr: errMissingAPIBase,
		},
		"InvalidAPIKey": {
			objects: []client.Object{
				providerConfig("credentials"),
				secret(map[string][]byte{"credentials": []byte(`{"api_base":"http://litellm:4000","api_key":123}`)}),
			},
			mg:      model("default"),
			wantErr: errMissingAPIKey,
		},
		"JSONCredentials": {
			objects: []client.Object{
				providerConfig("credentials"),
				secret(map[string][]byte{"credentials": []byte(`{"api_base":"http://litellm:4000","api_key":"k"}`)}),
			},
			mg:   model("default"),
			want: map[string]any{"api_base": "http://litellm:4000", "api_key": "k"},
		},
		"PerKeyCredentials": {
			objects: []client.Object{
				providerConfig("credentials"),
				secret(map[string][]byte{
					"api_base": []byte("http://litellm:4000"),
					"api_key":  []byte("k"),
				}),
			},
			mg:   model("default"),
			want: map[string]any{"api_base": "http://litellm:4000", "api_key": "k"},
		},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			kube := fake.NewClientBuilder().WithScheme(testScheme(t)).WithObjects(tc.objects...).Build()

			ps, err := TerraformSetupBuilder()(context.Background(), kube, tc.mg)
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("want error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			for k, v := range tc.want {
				if ps.Configuration[k] != v {
					t.Errorf("configuration[%q]: want %v, got %v", k, v, ps.Configuration[k])
				}
			}
			got, ok := ps.Meta.(*litellmProvider.Client)
			if !ok {
				t.Fatalf("setup metadata: want *litellm.Client, got %T", ps.Meta)
			}
			if got.APIBase != tc.want["api_base"] || got.APIKey != tc.want["api_key"] {
				t.Errorf("setup metadata client: want api_base %q and api_key %q, got %#v", tc.want["api_base"], tc.want["api_key"], got)
			}
		})
	}
}

func TestExtractCredentialsNoSecretRef(t *testing.T) {
	kube := fake.NewClientBuilder().WithScheme(testScheme(t)).Build()

	_, err := ExtractCredentials(context.Background(), xpv1.CredentialsSourceSecret, kube, xpv1.CommonCredentialSelectors{})
	if err == nil {
		t.Fatal("want error when secretRef is not set, got nil")
	}
}
