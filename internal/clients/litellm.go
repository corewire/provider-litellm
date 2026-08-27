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

// Package clients contains the LiteLLM Terraform provider setup function used
// by the upjet controller framework. It reads credentials from the referenced
// ProviderConfig Kubernetes secret and builds the configuration map that the
// embedded terraform-provider-litellm expects.
package clients

import (
	"context"
	"encoding/json"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	litellmProvider "github.com/BerriAI/terraform-provider-litellm/litellm"
	xpv1 "github.com/crossplane/crossplane-runtime/v2/apis/common/v1"
	"github.com/crossplane/crossplane-runtime/v2/pkg/errors"
	"github.com/crossplane/crossplane-runtime/v2/pkg/resource"
	"github.com/crossplane/upjet/v2/pkg/terraform"

	v1beta1 "github.com/corewire/provider-litellm/apis/v1beta1"
)

const (
	errNoProviderConfig     = "no providerConfigRef provided"
	errGetProviderConfig    = "cannot get referenced ProviderConfig"
	errExtractCredentials   = "cannot extract credentials"
	errUnmarshalCredentials = "cannot unmarshal litellm credentials as JSON"
	errGetCredentialsSecret = "cannot get credentials secret"
	errMissingAPIBase       = "required LiteLLM configuration key 'api_base' is missing"
	errMissingAPIKey        = "required LiteLLM configuration key 'api_key' is missing"
)

// TerraformSetupBuilder returns a terraform.SetupFn that reads the
// ProviderConfig credentials and translates them into the configuration map
// expected by the embedded terraform-provider-litellm.
func TerraformSetupBuilder() terraform.SetupFn {
	return func(ctx context.Context, kube client.Client, mg resource.Managed) (terraform.Setup, error) {
		ps := terraform.Setup{}

		// The provider config reference is not part of resource.Managed in
		// crossplane-runtime v2: cluster-scoped (legacy) managed resources
		// return an untyped reference while namespaced (modern) ones return a
		// typed reference. Support both.
		var pcName string
		switch mr := mg.(type) {
		case resource.ProviderConfigReferencer:
			if ref := mr.GetProviderConfigReference(); ref != nil {
				pcName = ref.Name
			}
		case resource.TypedProviderConfigReferencer:
			if ref := mr.GetProviderConfigReference(); ref != nil {
				pcName = ref.Name
			}
		}
		if pcName == "" {
			return ps, errors.New(errNoProviderConfig)
		}

		pc := &v1beta1.ProviderConfig{}
		if err := kube.Get(ctx, types.NamespacedName{Name: pcName}, pc); err != nil {
			return ps, errors.Wrap(err, errGetProviderConfig)
		}

		creds, err := ExtractCredentials(ctx, pc.Spec.Credentials.Source, kube, pc.Spec.Credentials.CommonCredentialSelectors)
		if err != nil {
			return ps, errors.Wrap(err, errExtractCredentials)
		}

		ps.Configuration = map[string]any{}
		for k, v := range creds {
			ps.Configuration[k] = v
		}

		apiBase, ok := ps.Configuration["api_base"].(string)
		if !ok || apiBase == "" {
			return ps, errors.New(errMissingAPIBase)
		}
		apiKey, ok := ps.Configuration["api_key"].(string)
		if !ok || apiKey == "" {
			return ps, errors.New(errMissingAPIKey)
		}

		ps.Meta = litellmProvider.NewClient(
			apiBase,
			apiKey,
			false,
		)

		return ps, nil
	}
}

// ExtractCredentials reads LiteLLM credentials from the referenced Kubernetes
// secret. If the secret has an entry matching the secretRef key, that value is
// treated as a JSON object. Otherwise, each key in the secret is treated as an
// individual configuration field.
func ExtractCredentials(ctx context.Context, source xpv1.CredentialsSource, kube client.Client, selector xpv1.CommonCredentialSelectors) (map[string]any, error) {
	creds := make(map[string]any)

	if selector.SecretRef == nil {
		return nil, errors.New("secretRef must be set in ProviderConfig credentials")
	}

	secret := &corev1.Secret{}
	if err := kube.Get(ctx, types.NamespacedName{
		Namespace: selector.SecretRef.Namespace,
		Name:      selector.SecretRef.Name,
	}, secret); err != nil {
		return nil, errors.Wrap(err, errGetCredentialsSecret)
	}

	// If the referenced key exists, parse the whole value as a JSON document.
	if raw, ok := secret.Data[selector.SecretRef.Key]; ok {
		if err := json.Unmarshal(raw, &creds); err != nil {
			// Fall through: maybe the value is plain text, not JSON.
			// Try the standard Crossplane credential extractor instead.
			rawData, extractErr := resource.CommonCredentialExtractor(ctx, source, kube, selector)
			if extractErr != nil {
				return nil, errors.Wrap(err, errUnmarshalCredentials)
			}
			if jsonErr := json.Unmarshal(rawData, &creds); jsonErr != nil {
				return nil, errors.Wrap(jsonErr, errUnmarshalCredentials)
			}
		}
		return creds, nil
	}

	// No matching key — treat every secret key as an individual field.
	for k, v := range secret.Data {
		creds[k] = string(v)
	}
	return creds, nil
}
