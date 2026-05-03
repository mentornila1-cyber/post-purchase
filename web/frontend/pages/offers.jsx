import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "react-query";
import {
  Page,
  Layout,
  Card,
  ResourceList,
  ResourceItem,
  TextField,
  Select,
  Checkbox,
  Button,
  ButtonGroup,
  Modal,
  FormLayout,
  Banner,
  Badge,
  Stack,
  TextStyle,
  EmptyState,
  Spinner,
} from "@shopify/polaris";
import { TitleBar, useAppBridge } from "@shopify/app-bridge-react";

const DEFAULT_FORM = {
  title: "",
  description: "",
  shopify_product_id: "",
  shopify_variant_id: "",
  image_url: "",
  original_price: "",
  currency: "USD",
  discount_type: "percentage",
  discount_value: "",
  trigger_product_ids: "",
  trigger_variant_ids: "",
  priority: "0",
  active: true,
};

const splitCsv = (raw) =>
  String(raw || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

const joinCsv = (arr) => (Array.isArray(arr) ? arr.join(", ") : "");

const firstCsvValue = (raw) => splitCsv(raw)[0] || "";

const findProduct = (products, productId) => products.find((product) => product.id === productId);

const findVariant = (products, variantId) =>
  products.flatMap((product) => product.variants || []).find((variant) => variant.id === variantId);

const productOptions = (products, selectedProductId) => {
  const options = [
    { label: "Select product", value: "" },
    ...products.map((product) => ({ label: product.title, value: product.id })),
  ];

  if (selectedProductId && !findProduct(products, selectedProductId)) {
    options.push({ label: `Current product (${selectedProductId})`, value: selectedProductId });
  }

  return options;
};

const variantOptions = (products, productId, selectedVariantId) => {
  const product = findProduct(products, productId);
  const options = [{ label: "Select variant", value: "" }];

  if (product) {
    options.push(
      ...product.variants.map((variant) => ({
        label: variant.title === "Default Title" ? product.title : `${product.title} - ${variant.title}`,
        value: variant.id,
      })),
    );
  }

  if (selectedVariantId && !findVariant(products, selectedVariantId)) {
    options.push({ label: `Current variant (${selectedVariantId})`, value: selectedVariantId });
  }

  return options;
};

const offerToForm = (offer) => ({
  title: offer.title || "",
  description: offer.description || "",
  shopify_product_id: offer.shopify_product_id || "",
  shopify_variant_id: offer.shopify_variant_id || "",
  image_url: offer.image_url || "",
  original_price: offer.original_price ?? "",
  currency: offer.currency || "USD",
  discount_type: offer.discount_type || "percentage",
  discount_value: offer.discount_value ?? "",
  trigger_product_ids: joinCsv(offer.trigger_product_ids),
  trigger_variant_ids: joinCsv(offer.trigger_variant_ids),
  priority: String(offer.priority ?? 0),
  active: !!offer.active,
});

const calculateDiscountedPrice = (form) => {
  const originalPrice = Number(form.original_price);
  const discountValue = Number(form.discount_value);

  if (!Number.isFinite(originalPrice) || originalPrice <= 0) return null;
  if (!Number.isFinite(discountValue) || discountValue <= 0) return originalPrice;

  const discounted =
    form.discount_type === "fixed_amount"
      ? originalPrice - discountValue
      : originalPrice * (1 - discountValue / 100);

  return Number(Math.max(discounted, 0).toFixed(2));
};

const formToPayload = (form) => ({
  offer: {
    ...form,
    priority: Number(form.priority) || 0,
    discount_value: form.discount_value === "" ? null : Number(form.discount_value),
    original_price: form.original_price === "" ? null : Number(form.original_price),
    discounted_price: calculateDiscountedPrice(form),
    trigger_product_ids: splitCsv(form.trigger_product_ids),
    trigger_variant_ids: splitCsv(form.trigger_variant_ids),
  },
});

export default function OffersPage() {
  const shopify = useAppBridge();
  const queryClient = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editingOffer, setEditingOffer] = useState(null);
  const [form, setForm] = useState(DEFAULT_FORM);
  const [errors, setErrors] = useState([]);

  const { data: offers = [], isLoading } = useQuery({
    queryKey: ["offers"],
    queryFn: async () => {
      const res = await fetch("/api/offers");
      if (!res.ok) throw new Error("Failed to load offers");
      return res.json();
    },
  });

  const {
    data: products = [],
    isLoading: productsLoading,
    isError: productsError,
  } = useQuery({
    queryKey: ["shopify-products"],
    queryFn: async () => {
      const res = await fetch("/api/shopify/products");
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || "Failed to load Shopify products");
      return body;
    },
  });

  const saveMutation = useMutation({
    mutationFn: async () => {
      const url = editingOffer ? `/api/offers/${editingOffer.id}` : "/api/offers";
      const method = editingOffer ? "PATCH" : "POST";
      const res = await fetch(url, {
        method,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(formToPayload(form)),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error((body.errors || ["Save failed"]).join(", "));
      return body;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["offers"] });
      shopify.toast.show(editingOffer ? "Offer updated" : "Offer created");
      closeModal();
    },
    onError: (error) => {
      setErrors([error.message]);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: async (id) => {
      const res = await fetch(`/api/offers/${id}`, { method: "DELETE" });
      if (!res.ok && res.status !== 204) throw new Error("Delete failed");
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["offers"] });
      shopify.toast.show("Offer deleted");
    },
    onError: () => shopify.toast.show("Delete failed", { isError: true }),
  });

  const toggleActiveMutation = useMutation({
    mutationFn: async (offer) => {
      const res = await fetch(`/api/offers/${offer.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ offer: { active: !offer.active } }),
      });
      if (!res.ok) throw new Error("Update failed");
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["offers"] }),
    onError: () => shopify.toast.show("Update failed", { isError: true }),
  });

  const openCreate = () => {
    setEditingOffer(null);
    setForm(DEFAULT_FORM);
    setErrors([]);
    setModalOpen(true);
  };

  const openEdit = (offer) => {
    setEditingOffer(offer);
    setForm(offerToForm(offer));
    setErrors([]);
    setModalOpen(true);
  };

  const closeModal = () => {
    setModalOpen(false);
    setEditingOffer(null);
    setErrors([]);
  };

  const updateField = (field) => (value) => setForm((f) => ({ ...f, [field]: value }));
  const previewDiscountedPrice = calculateDiscountedPrice(form);
  const triggerProductId = firstCsvValue(form.trigger_product_ids);
  const triggerVariantId = firstCsvValue(form.trigger_variant_ids);

  const selectOfferProduct = (productId) => {
    const product = findProduct(products, productId);
    const variant = product?.variants[0];

    setForm((current) => ({
      ...current,
      title: current.title || product?.title || "",
      shopify_product_id: productId,
      shopify_variant_id: variant?.id || "",
      image_url: current.image_url || product?.image_url || "",
      original_price: variant ? String(variant.price) : "",
    }));
  };

  const selectOfferVariant = (variantId) => {
    const variant = findVariant(products, variantId);

    setForm((current) => ({
      ...current,
      shopify_variant_id: variantId,
      original_price: variant ? String(variant.price) : current.original_price,
    }));
  };

  const selectTriggerProduct = (productId) => {
    const product = findProduct(products, productId);
    const variant = product?.variants[0];

    setForm((current) => ({
      ...current,
      trigger_product_ids: productId,
      trigger_variant_ids: variant?.id || "",
    }));
  };

  const selectTriggerVariant = (variantId) => {
    setForm((current) => ({ ...current, trigger_variant_ids: variantId }));
  };

  if (isLoading) {
    return (
      <Page>
        <Spinner />
      </Page>
    );
  }

  return (
    <Page
      title="Offers"
      primaryAction={{ content: "Create offer", onAction: openCreate }}
    >
      <TitleBar title="Offers" />
      <Layout>
        <Layout.Section>
          <Card>
            {offers.length === 0 ? (
              <EmptyState
                heading="No offers yet"
                action={{ content: "Create offer", onAction: openCreate }}
              >
                <p>Create an offer to start running post-purchase upsells.</p>
              </EmptyState>
            ) : (
              <ResourceList
                resourceName={{ singular: "offer", plural: "offers" }}
                items={offers}
                renderItem={(offer) => (
                  <ResourceItem
                    id={String(offer.id)}
                    accessibilityLabel={`Edit ${offer.title}`}
                    onClick={() => openEdit(offer)}
                  >
                    <Stack alignment="center" distribution="equalSpacing">
                      <Stack vertical spacing="extraTight">
                        <Stack alignment="center" spacing="tight">
                          <TextStyle variation="strong">{offer.title}</TextStyle>
                          {offer.active ? (
                            <Badge status="success">Active</Badge>
                          ) : (
                            <Badge>Inactive</Badge>
                          )}
                          <Badge>{`Priority ${offer.priority ?? 0}`}</Badge>
                        </Stack>
                        <TextStyle variation="subdued">
                          {`${offer.currency || "USD"} ${offer.discounted_price || "—"} (was ${
                            offer.original_price || "—"
                          })`}
                        </TextStyle>
                      </Stack>
                      <ButtonGroup>
                        <Button
                          onClick={(e) => {
                            e?.stopPropagation?.();
                            toggleActiveMutation.mutate(offer);
                          }}
                        >
                          {offer.active ? "Deactivate" : "Activate"}
                        </Button>
                        <Button
                          destructive
                          onClick={(e) => {
                            e?.stopPropagation?.();
                            if (window.confirm(`Delete "${offer.title}"?`)) {
                              deleteMutation.mutate(offer.id);
                            }
                          }}
                        >
                          Delete
                        </Button>
                      </ButtonGroup>
                    </Stack>
                  </ResourceItem>
                )}
              />
            )}
          </Card>
        </Layout.Section>
      </Layout>

      <Modal
        open={modalOpen}
        onClose={closeModal}
        title={editingOffer ? `Edit "${editingOffer.title}"` : "Create offer"}
        primaryAction={{
          content: editingOffer ? "Save" : "Create",
          loading: saveMutation.isLoading,
          onAction: () => saveMutation.mutate(),
        }}
        secondaryActions={[{ content: "Cancel", onAction: closeModal }]}
        large
      >
        <Modal.Section>
          {errors.length > 0 && (
            <Banner status="critical" title="Could not save">
              <ul>{errors.map((e) => <li key={e}>{e}</li>)}</ul>
            </Banner>
          )}
          <FormLayout>
            <TextField label="Title" value={form.title} onChange={updateField("title")} autoComplete="off" />
            <TextField
              label="Description"
              value={form.description}
              onChange={updateField("description")}
              multiline={2}
              autoComplete="off"
            />

            {productsError ? (
              <Banner status="critical">
                Could not load active Shopify products. Confirm the app has product access scopes
                and reinstall if scopes changed.
              </Banner>
            ) : null}

            <FormLayout.Group>
              <Select
                label="Offer product"
                options={productOptions(products, form.shopify_product_id)}
                value={form.shopify_product_id}
                onChange={selectOfferProduct}
                disabled={productsLoading || productsError}
              />
              <Select
                label="Offer variant"
                options={variantOptions(products, form.shopify_product_id, form.shopify_variant_id)}
                value={form.shopify_variant_id}
                onChange={selectOfferVariant}
                disabled={productsLoading || productsError || !form.shopify_product_id}
              />
            </FormLayout.Group>

            <TextField
              label="Image URL"
              value={form.image_url}
              onChange={updateField("image_url")}
              autoComplete="off"
            />

            <FormLayout.Group>
              <TextField
                label="Original price"
                type="number"
                value={form.original_price}
                onChange={updateField("original_price")}
                helpText="Filled from the selected Shopify variant. You can override for demo data."
                autoComplete="off"
              />
              <TextField
                label="Currency"
                value={form.currency}
                onChange={updateField("currency")}
                autoComplete="off"
              />
            </FormLayout.Group>

            <FormLayout.Group>
              <Select
                label="Discount type"
                options={[
                  { label: "Percentage", value: "percentage" },
                  { label: "Fixed amount", value: "fixed_amount" },
                ]}
                value={form.discount_type}
                onChange={updateField("discount_type")}
              />
              <TextField
                label="Discount value"
                type="number"
                value={form.discount_value}
                onChange={updateField("discount_value")}
                autoComplete="off"
              />
              <TextField
                label="Priority"
                type="number"
                value={form.priority}
                onChange={updateField("priority")}
                autoComplete="off"
              />
            </FormLayout.Group>

            <Banner>
              Discounted price preview:{" "}
              <TextStyle variation="strong">
                {form.currency || "USD"}{" "}
                {previewDiscountedPrice == null ? "—" : previewDiscountedPrice.toFixed(2)}
              </TextStyle>
            </Banner>

            <FormLayout.Group>
              <Select
                label="Trigger product"
                options={productOptions(products, triggerProductId)}
                value={triggerProductId}
                onChange={selectTriggerProduct}
                disabled={productsLoading || productsError}
              />
              <Select
                label="Trigger variant"
                options={variantOptions(products, triggerProductId, triggerVariantId)}
                value={triggerVariantId}
                onChange={selectTriggerVariant}
                disabled={productsLoading || productsError || !triggerProductId}
              />
            </FormLayout.Group>

            <Checkbox label="Active" checked={form.active} onChange={updateField("active")} />
          </FormLayout>
        </Modal.Section>
      </Modal>
    </Page>
  );
}
