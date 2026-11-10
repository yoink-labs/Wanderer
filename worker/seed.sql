-- Public Explore content. Safe to run multiple times.
-- IDs match the Supabase seed so an import is a no-op.

INSERT INTO guides (id, title, summary, destination, is_published)
VALUES
    ('11111111-1111-4111-8111-111111111111', '48 hours in Kyoto', 'A first-timer''s route through shrines, coffee and the Kamo river.', 'Kyoto, Japan', 1),
    ('22222222-2222-4222-8222-222222222222', 'Lisbon in a long weekend', 'Pastel streets, miradouros and the best custard tart in town.', 'Lisbon, Portugal', 1),
    ('33333333-3333-4333-8333-333333333333', 'Reykjavík road trip', 'Waterfalls, black sand and hot springs along the south coast.', 'Reykjavík, Iceland', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO guide_places (id, guide_id, name, address, lat, lng, notes, position)
VALUES
    ('11111111-1111-4111-8111-000000000001', '11111111-1111-4111-8111-111111111111', 'Fushimi Inari Shrine', '68 Fukakusa Yabunouchicho, Kyoto', 34.9671, 135.7727, 'Go before 8am to beat the crowd.', 0),
    ('11111111-1111-4111-8111-000000000002', '11111111-1111-4111-8111-111111111111', 'Nishiki Market', 'Nishikikoji-dori, Kyoto', 35.0050, 135.7649, 'Graze the whole street; cash is useful.', 1),
    ('11111111-1111-4111-8111-000000000003', '11111111-1111-4111-8111-111111111111', 'Kinkaku-ji', '1 Kinkakujicho, Kita Ward, Kyoto', 35.0394, 135.7292, 'Golden pavilion; pair with Ryoan-ji.', 2),
    ('22222222-2222-4222-8222-000000000001', '22222222-2222-4222-8222-222222222222', 'Castelo de São Jorge', 'R. de Santa Cruz do Castelo, Lisbon', 38.7139, -9.1335, 'Best at golden hour.', 0),
    ('22222222-2222-4222-8222-000000000002', '22222222-2222-4222-8222-222222222222', 'Time Out Market', 'Av. 24 de Julho 49, Lisbon', 38.7071, -9.1459, 'One stop for a lot of local food.', 1),
    ('22222222-2222-4222-8222-000000000003', '22222222-2222-4222-8222-222222222222', 'Miradouro da Senhora do Monte', 'Largo Monte, Lisbon', 38.7192, -9.1327, 'The quietest sunset viewpoint.', 2),
    ('33333333-3333-4333-8333-000000000001', '33333333-3333-4333-8333-333333333333', 'Seljalandsfoss', 'South coast, Iceland', 63.6156, -19.9886, 'Walk behind the waterfall; bring a rain shell.', 0),
    ('33333333-3333-4333-8333-000000000002', '33333333-3333-4333-8333-333333333333', 'Reynisfjara Black Sand Beach', 'Vík, Iceland', 63.4043, -19.0448, 'Never turn your back on the waves.', 1),
    ('33333333-3333-4333-8333-000000000003', '33333333-3333-4333-8333-333333333333', 'Blue Lagoon', 'Norðurljósavegur 9, Grindavík', 63.8804, -22.4495, 'Book a slot before you fly home.', 2)
ON CONFLICT (id) DO NOTHING;
