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

// Package config contains the upjet provider configuration for provider-litellm.
package config

import (
	// Note(turkenh): we are importing this to embed provider schema document
	_ "embed"

	ujconfig "github.com/crossplane/upjet/v2/pkg/config"
	conversiontfjson "github.com/crossplane/upjet/v2/pkg/types/conversion/tfjson"
	tfjson "github.com/hashicorp/terraform-json"
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/schema"
	litellmProvider "github.com/BerriAI/terraform-provider-litellm/litellm"
	"github.com/pkg/errors"
)

const (
	resourcePrefix = "litellm"
	modulePath     = "github.com/corewire/provider-litellm"
	rootGroup      = "litellm.crossplane.io"
)

//go:embed schema.json
var providerSchema string

//go:embed provider-metadata.yaml
var providerMetadata string

// getProviderSchema converts the embedded JSON schema to a *schema.Provider
// so the generator can derive Go types from it without needing a live TF binary.
func getProviderSchema(s string) (*schema.Provider, error) {
	ps := tfjson.ProviderSchemas{}
	if err := ps.UnmarshalJSON([]byte(s)); err != nil {
		panic(err)
	}
	if len(ps.Schemas) != 1 {
		return nil, errors.Errorf("there should exactly be 1 provider schema but there are %d", len(ps.Schemas))
	}
	var rs map[string]*tfjson.Schema
	for _, v := range ps.Schemas {
		rs = v.ResourceSchemas
		break
	}
	return &schema.Provider{
		ResourcesMap: conversiontfjson.GetV2ResourceMap(rs),
	}, nil
}

// GetProvider returns the upjet provider configuration used by the code
// generator (generationProvider=true) and by the controller manager at runtime
// (generationProvider=false).
func GetProvider(generationProvider bool) (*ujconfig.Provider, error) {
	var p *schema.Provider
	var err error
	if generationProvider {
		p, err = getProviderSchema(providerSchema)
		if err != nil {
			return nil, errors.Wrap(err, "cannot get the Terraform provider schema")
		}
	} else {
		p = litellmProvider.Provider()
	}

	pc := ujconfig.NewProvider([]byte(providerSchema), resourcePrefix, modulePath, []byte(providerMetadata),
		ujconfig.WithIncludeList([]string{}),
		ujconfig.WithTerraformPluginSDKIncludeList(ExternalNameConfigured()),
		ujconfig.WithTerraformPluginFrameworkIncludeList([]string{}),
		ujconfig.WithTerraformProvider(p),
		ujconfig.WithFeaturesPackage("internal/features"),
		ujconfig.WithDefaultResourceOptions(
			ExternalNameConfigurations(),
		),
		ujconfig.WithRootGroup(rootGroup),
	)

	for _, configure := range []func(provider *ujconfig.Provider){
		// add custom config functions here per resource group
	} {
		configure(pc)
	}

	pc.ConfigureResources()
	return pc, nil
}
