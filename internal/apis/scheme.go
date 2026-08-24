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

// Package apis holds the runtime scheme used by the generated cross-resource
// reference resolvers to look up managed resources by GroupVersionKind.
package apis

import (
	xpresource "github.com/crossplane/crossplane-runtime/v2/pkg/resource"
	"github.com/pkg/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
)

var s = runtime.NewScheme()

// GetManagedResource returns a new managed resource and managed resource list
// of the given GroupVersionKind from the resolver's runtime scheme.
func GetManagedResource(group, version, kind, listKind string) (xpresource.Managed, xpresource.ManagedList, error) {
	gv := schema.GroupVersion{
		Group:   group,
		Version: version,
	}
	kindGVK := gv.WithKind(kind)
	m, err := s.New(kindGVK)
	if err != nil {
		return nil, nil, errors.Wrapf(err, "failed to get a new API object of GVK %q from the runtime scheme", kindGVK)
	}

	listGVK := gv.WithKind(listKind)
	l, err := s.New(listGVK)
	if err != nil {
		return nil, nil, errors.Wrapf(err, "failed to get a new API object list of GVK %q from the runtime scheme", listGVK)
	}
	return m.(xpresource.Managed), l.(xpresource.ManagedList), nil
}

// BuildScheme registers the given API types with the resolver's runtime scheme.
func BuildScheme(sb runtime.SchemeBuilder) error {
	return errors.Wrap(sb.AddToScheme(s), "failed to register the GVKs with the runtime scheme")
}
