class DummyBook {
  final String id;
  final String title;
  final String author;
  final String description;
  final String image;
  final double price;
  final bool isTrending;
  final bool isNewRelease;
  final bool isKenyanAuthor;
  final bool isLocalLanguage;
  final bool isAudiobook;
  final bool isEbook;

  DummyBook({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.image,
    required this.price,
    this.isTrending = false,
    this.isNewRelease = false,
    this.isKenyanAuthor = false,
    this.isLocalLanguage = false,
    this.isAudiobook = false,
    this.isEbook = true,
  });
}

final dummyBooks = [
  DummyBook(
    id: '1',
    title: 'The Silent Path',
    author: 'Barak Wandera',
    description: 'A deep African story of identity and courage. Journey through landscapes of self-discovery.',
    image: 'lib/assets/image.png',
    price: 650,
    isTrending: true,
    isKenyanAuthor: true,
    isEbook: true,
  ),
  DummyBook(
    id: '2',
    title: 'Echoes of Tomorrow',
    author: 'Faith Njeri',
    description: 'Hope, struggle and the future. A powerful narrative about resilience and dreams.',
    image: 'lib/assets/mourning.png',
    price: 700,
    isNewRelease: true,
    isKenyanAuthor: true,
    isEbook: true,
  ),
  DummyBook(
    id: '3',
    title: 'Roots & Wings',
    author: 'Daniel Otieno',
    description: 'Stories of growth and belonging. Exploring heritage and modern identity.',
    image: 'lib/assets/whispers.png',
    price: 600,
    isTrending: true,
    isKenyanAuthor: true,
    isAudiobook: true,
  ),
  DummyBook(
    id: '4',
    title: 'Voices in the Storm',
    author: 'Grace Kipchoge',
    description: 'Chronicles of triumph over adversity. A gripping tale of personal transformation.',
    image: 'lib/assets/hitlers.png',
    price: 750,
    isNewRelease: true,
    isKenyanAuthor: true,
    isEbook: true,
  ),
  DummyBook(
    id: '5',
    title: 'Ubuntu Stories',
    author: 'James Kariuki',
    description: 'Celebrating African values and community. Tales told in Swahili and English.',
    image: 'lib/assets/birds.png',
    price: 550,
    isKenyanAuthor: true,
    isLocalLanguage: true,
    isAudiobook: true,
  ),
  DummyBook(
    id: '6',
    title: 'Pandemic Chronicles',
    author: 'Dr. Margaret Ouma',
    description: 'A historical account of challenges and human spirit. Insights from the frontlines.',
    image: 'lib/assets/pandemic.png',
    price: 800,
    isNewRelease: true,
    isKenyanAuthor: true,
    isEbook: true,
  ),
  DummyBook(
    id: '7',
    title: 'Maangavu: The Forgotten Legacy',
    author: 'Samuel Mutua',
    description: 'A journey through time and memory. Preserving stories for future generations.',
    image: 'lib/assets/maangavu.png',
    price: 680,
    isTrending: true,
    isKenyanAuthor: true,
    isLocalLanguage: true,
    isAudiobook: true,
  ),
];

// Helper lists for different sections
final trendingBooks = dummyBooks.where((book) => book.isTrending).toList();
final newReleases = dummyBooks.where((book) => book.isNewRelease).toList();
final kenyanAuthors = dummyBooks.where((book) => book.isKenyanAuthor).toList();
final localLanguageBooks = dummyBooks.where((book) => book.isLocalLanguage).toList();
final audiobooksList = dummyBooks.where((book) => book.isAudiobook).toList();
final ebooksList = dummyBooks.where((book) => book.isEbook).toList();
